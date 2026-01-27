defmodule BskyLabeler.Websocket do
  alias BskyLabeler.AtEvents
  alias Wesex.Connection
  import System, only: [system_time: 0]
  require Logger

  use GenServer

  @instances ["jetstream1.us-east.bsky.network", "jetstream2.us-east.bsky.network"]
  @retry_time 15_000

  def start_link(opts) do
    # {wesex_opts, genserver_opts} = Keyword.split(opts, [:url, :headers, :adapter_opts, :init_arg])
    {config, genserver_opts} = Keyword.split(opts, [:labeler_did, :session_manager, :min_likes])
    genserver_opts = Keyword.put_new(genserver_opts, :name, __MODULE__)

    GenServer.start_link(__MODULE__, config, genserver_opts)
  end

  @impl GenServer
  def init(config) do
    labeler_did = config[:labeler_did]
    session_manager = config[:session_manager]
    true = !!labeler_did
    true = !!session_manager

    Process.flag(:trap_exit, true)

    {:ok,
     %{
       conn: nil,
       counter: %{},
       reconnect_timer: nil,
       labeler_did: labeler_did,
       session_manager: session_manager,
       min_likes: config[:min_likes] || 50
     }, {:continue, :connect}}
  end

  @impl GenServer
  def handle_continue(:connect, state) do
    nil = state.conn
    instance = Enum.random(@instances)

    uri = %URI{
      scheme: "wss",
      host: instance,
      port: 443,
      path: "/subscribe",
      query: "wantedCollections=app.bsky.feed.post&wantedCollections=app.bsky.feed.like"
    }

    Logger.info("URI: #{uri}")
    # TELEMETRY
    case Connection.connect(uri, [], Wesex.MintAdapter, conn: [protocols: [:http1]]) do
      {:ok, conn} ->
        :telemetry.execute([:bsky_labeler, :ws_connect, :ok], %{system_time: system_time()})
        {:noreply, %{state | conn: conn}}

      {:error, reason} ->
        :telemetry.execute([:bsky_labeler, :ws_connect, :error], %{system_time: system_time()}, %{
          error: reason
        })

        Logger.error(
          "Error when trying to connect: #{inspect(reason)}. Retrying in #{@retry_time}"
        )

        timer = Process.send_after(self(), :retry, @retry_time)
        {:noreply, %{state | reconnect_timer: timer}}
    end
  end

  @impl GenServer
  def handle_info(:retry, state) do
    state = %{state | reconnect_timer: nil}
    handle_continue(:connect, state)
  end

  def handle_info(info, %{conn: nil} = state) do
    Logger.debug("Message received when conn nil: #{inspect(info, limit: 3)}")
    {:noreply, state}
  end

  def handle_info(info, %{conn: conn} = state) do
    {events, c} = Connection.event(conn, info)
    do_events(%{state | conn: c}, events)
  end

  @impl GenServer
  def terminate(reason, state) do
    if (reason == :shutdown or match?({:shutdown, _}, reason)) and state.conn do
      Logger.info("Shutting down, sending close 1000")
      {events, conn} = Connection.close(state.conn, {1000, nil})
      receive_until_close(events, conn)
    else
      # TELEMETRY
      :telemetry.execute(
        [:bsky_labeler, :ws_terminate_non_shutdown],
        %{system_time: system_time()},
        %{
          reason: reason
        }
      )
    end
  end

  defp receive_until_close([], conn) do
    receive do
      info ->
        case Connection.event(conn, info) do
          false ->
            Logger.warning("Received unhandled message: " <> inspect(info))

          {result_events, conn} ->
            receive_until_close(result_events, conn)
        end
    end
  end

  defp receive_until_close([{:received, {:text, _post}} | rest], conn) do
    # Logger.debug("Received after sent close:\n" <> post)
    receive_until_close(rest, conn)
  end

  defp receive_until_close([{:closing, reason} | rest], conn) do
    Logger.info("Closing: " <> inspect(reason))
    receive_until_close(rest, conn)
  end

  defp receive_until_close([{:closed, reason} | _rest], _conn) do
    Logger.info("Closed: " <> inspect(reason))
  end

  defp do_events(state, []), do: {:noreply, state}

  defp do_events(state, [{:received, {:text, atevent_json}} | rest]) do
    atevent = Jason.decode!(atevent_json)
    state = AtEvents.receive(atevent, state)
    do_events(state, rest)
  end

  defp do_events(state, [:open | rest]) do
    Logger.info("Open")
    do_events(state, rest)
  end

  defp do_events(state, [{:closing, reason} | rest]) do
    Logger.info("Closing: " <> inspect(reason))
    do_events(state, rest)
  end

  defp do_events(state, [{:closed, reason} | _rest]) do
    # reason: {:remote, {1000..4999 | nil, binary() | nil}}
    #          | {:error, :timeout | :aborted | :closed_in_handshake | :unexpected_tcp_close}}
    # TELEMETRY
    :telemetry.execute([:bsky_labeler, :ws_closed], %{system_time: system_time()}, %{
      reason: reason
    })

    Logger.error("Remote closed with #{inspect(reason)}. Reconnecting in #{@retry_time}")

    timer = Process.send_after(self(), :retry, @retry_time)
    {:noreply, %{state | reconnect_timer: timer, conn: nil}}
  end
end
