defmodule BskyLabeler.Utils.WebsocketProducer do
  @moduledoc """
  A `GenStage` **producer** that connects to a websocket server and emits received data as events.

  Start options
  * `:uri` — (required) A URI or a string, or a function that returns one of the former.

  * `:headers` — The list of additional headers for the connection.

  * `:flat_mapper` — Used to filter and transform events before they are emitted.
        In the shape of `%{acc: acc, fun: ((el, acc) -> {[new_els], new_acc})}`,
        where `acc` is an accumulator that is given to the function and replaced
        with each invocation; `el` is an event. If `nil` (default), acts as
        `%{acc: nil, fun: fn el, acc -> {[el], acc} end}`

  * `:event_cb` — A callback function that is called on non-produced events.
        It accepts one of the following arguments; its return value is discarded.

    * `{:connecting, uri}` — Connecting to the uri.
    * `{:connect_error, reason, reconnect_after}` — Connection failed. `reason` is an exception.
          Connection will be re-attempted after `reconnect_after` milliseconds.
    * `:open` — The connection is now accepting data.
    * `{:closing, reason}` — The connection is closing. `reason` is `t:closing_reason/0`

    * `{:closed, reason, reconnect_after}` — The connection is closed. `reason` is `t:closed_reason/0`
          If the process is terminating, `reconnect_after` is nil.

  When started, the stage will immediately connect.
  It will only receive network responses when there is demand.

  After a disconnect, the stage will reconnect after 15 seconds.

  When exiting with a "shutdown" reason, it will properly close the websocket connection.
  """

  alias Wesex.Connection
  require Logger
  use GenStage

  @type closing_reason ::
          {:local, stop_code_reason()} | {:remote, stop_code_reason()}

  @type closed_reason ::
          {:remote, stop_code_reason()}
          | {:error, :timeout | :aborted | :closed_in_handshake | :unexpected_tcp_close}

  @type stop_code_reason() :: {1000..4999 | nil, binary() | nil}

  @reconnect_after 15_000

  def start_link(opts) do
    keys = [:uri, :headers, :flat_mapper, :event_cb]
    {config, gen_server_opts} = Keyword.split(opts, keys)
    Keyword.validate!(config, keys)
    GenStage.start_link(__MODULE__, config, gen_server_opts)
  end

  def buffered_demand(producer) do
    GenStage.call(producer, :get_buffered_demand)
  end

  @impl GenStage
  def init(config) do
    # By default, pass as is
    flat_mapper =
      config[:flat_mapper] ||
        %{
          acc: nil,
          fun: fn el, acc -> {[el], acc} end
        }

    # Connect immediately after
    timer = Process.send_after(self(), :connect_timer, 0)

    state = %{
      uri: config[:uri],
      headers: config[:headers] || [],
      flat_mapper: flat_mapper,
      event_cb: config[:event_cb],
      conn: nil,
      remaining_demand: 0,
      messages: :queue.new(),
      connect_timer: timer
    }

    # So we can close gracefully on shutdown
    Process.flag(:trap_exit, true)

    {:producer, state, buffer_size: :infinity}
  end

  @impl GenStage
  def terminate(reason, state) do
    # The state may be bad if other reason, so don't attempt closing
    if (reason == :shutdown or match?({:shutdown, _}, reason)) and state.conn do
      # Run Wesex through the buffered messages before proceeding with the receive loop

      {queued_events, conn} =
        state.messages
        |> :queue.to_list()
        |> Enum.flat_map_reduce(
          state.conn,
          fn msg, conn ->
            Connection.event(conn, msg) ||
              (
                tap_unhandled_message(msg)
                {[], conn}
              )
          end
        )

      if Connection.status(conn) != :closed do
        {events, conn} = Connection.close(conn, {1000, nil})
        receive_until_close(queued_events ++ events, conn, state.event_cb)
      end
    end
  end

  # Recursively receive until the :closed event
  defp receive_until_close([], conn, event_cb) do
    receive do
      info when not (is_tuple(info) and elem(info, 0) == :"$gen_producer") ->
        case Connection.event(conn, info) do
          false -> tap_unhandled_message(info)
          {result_events, conn} -> receive_until_close(result_events, conn, event_cb)
        end
    end
  end

  defp receive_until_close([{:received, {:text, _post}} | rest], conn, event_cb) do
    # Logger.debug("Received after sent close:\n" <> post)
    receive_until_close(rest, conn, event_cb)
  end

  defp receive_until_close([{:closing, reason} | rest], conn, event_cb) do
    callback(event_cb, {:closing, reason})
    receive_until_close(rest, conn, event_cb)
  end

  defp receive_until_close([{:closed, reason} | _rest], _conn, event_cb) do
    callback(event_cb, {:closed, reason, nil})
  end

  @impl GenStage
  def handle_call(:get_buffered_demand, _, state) do
    {:reply, state.remaining_demand, [], state}
  end

  @impl GenStage
  # Either a first time connect or a reconnect
  def handle_info(:connect_timer, state) do
    state = %{state | connect_timer: nil}

    # A function is useful for choosing from multiple URIs, or adjusting a cursor param.
    uri =
      if is_function(state.uri) do
        state.uri.()
      else
        state.uri
      end

    callback(state.event_cb, {:connecting, uri})

    case Connection.connect(uri, state.headers, Wesex.MintAdapter, conn: [protocols: [:http1]]) do
      {:ok, conn} ->
        # Status is now :handshaking
        conn = %{conn | ping_timeout: fn -> nil end}
        {:noreply, [], %{state | conn: conn}}

      {:error, reason} ->
        # Retry again
        timer = Process.send_after(self(), :retry, @reconnect_after)

        callback(state.event_cb, {:connect_error, reason, @reconnect_after})

        {:noreply, [], %{state | connect_timer: timer}}
    end
  end

  def handle_info(message, state) do
    # Store the messages in a queue we can Connection.event/2 them later on demand
    state = update_in(state.messages, &:queue.in(message, &1))

    cond do
      state.remaining_demand == 0 ->
        # New websocket messages arrive only after each Wesex.Connection.event/2 call (which calls Mint.WebSocket.stream/2)
        # Not calling that blocks the websocket connection upstream.
        {:noreply, [], state}

      state.remaining_demand > 0 ->
        handle_additional_demand(0, state)
    end
  end

  @impl GenStage
  def handle_demand(demand, state) do
    handle_additional_demand(demand, state)
  end

  defp handle_additional_demand(demand, state) do
    # Run the event/2 over the message queue
    {conn, datas, flat_mapper} =
      stream_all_messages(state.conn, state.messages, state.flat_mapper, state.event_cb)

    # Connection might have gotten closed while event/2 'ing
    timer =
      if !state.connect_timer and Wesex.Connection.status(conn) == :closed do
        Process.send_after(self(), :connect_timer, @reconnect_after)
      else
        state.connect_timer
      end

    count = Enum.count(datas)

    remaining_demand = (state.remaining_demand + (demand - count)) |> max(0)
    # There might be more data events than demanded, but no problem to let
    # them into the GenStage's built-in buffer

    state = %{
      state
      | conn: conn,
        messages: :queue.new(),
        flat_mapper: flat_mapper,
        remaining_demand: remaining_demand,
        connect_timer: timer
    }

    {:noreply, datas, state}
  end

  defp stream_all_messages(conn, messages, flat_mapper, event_cb) do
    case :queue.out(messages) do
      {:empty, _messages} ->
        # Empty queue, no events
        {conn, [], flat_mapper}

      {{:value, message}, messages} ->
        case Wesex.Connection.event(conn, message) do
          # return the data responses, run callback on others (probs for telemetry)
          {events, conn} ->
            datas = Enum.flat_map(events, &do_events(&1, event_cb))

            # User defined filter & transform
            {datas, flat_mapper_acc} =
              Enum.flat_map_reduce(datas, flat_mapper.acc, flat_mapper.fun)

            flat_mapper = %{flat_mapper | acc: flat_mapper_acc}

            # Recurse, do the rest
            {conn, datas_rest, flat_mapper} =
              stream_all_messages(conn, messages, flat_mapper, event_cb)

            {conn, datas ++ datas_rest, flat_mapper}

          false ->
            # Unexpected message, log and continue
            tap_unhandled_message(message)
            stream_all_messages(conn, messages, flat_mapper, event_cb)
        end
    end
  end

  defp do_events(:open, event_cb) do
    callback(event_cb, :open)
    []
  end

  defp do_events({:received, data}, _) do
    # data is {:text | :binary, binary()}
    [data]
  end

  defp do_events({:closing, reason}, event_cb) do
    callback(event_cb, {:closing, reason})
    []
  end

  defp do_events({:closed, reason}, event_cb) do
    callback(event_cb, {:closed, reason, @reconnect_after})
    []
  end

  defp callback(nil, _), do: nil
  defp callback(fun, arg), do: fun.(arg)

  defp tap_unhandled_message(message) do
    Logger.warning("Unhandled message received in websocket process: #{inspect(message)}")
  end
end
