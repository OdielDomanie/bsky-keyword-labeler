defmodule Ocr.QueueManager do
  @moduledoc """
  Allows for limiting instances of running a function and provides back-pressure.

  The given function will run immediately if the count of concurrent instances is
  less then `max_current`. If more, it is queued as FIFO.

  The function is run in the caller process.

  The count of concurrent instances are subtracted after the function completes,
  or raises/throws, or if the caller process exits.

  The caller is removed from the queue if it exits.
  """

  use GenServer
  import System, only: [monotonic_time: 0]

  @type manager :: GenServer.server()

  @doc """
  Blocks until given pass by the manager, then returns the result of the given function inside the `ok` tuple.

  If the internal queue is longer than max_queue_size, returns `:queue_full`.

  If the process is down or goes down, returns `:down`.

  When pass is obtained, telemetry event is emitted:
  `[:ocr_server, :queue_manager_pass], %{duration: queue_dur}, %{manager: manager}`
  """
  @spec command(manager(), (-> term()), timeout()) ::
          {:ok, term()} | :queue_full | :down
  def command(manager, fun, max_queue_size) do
    queue_start = monotonic_time()

    # cast/2, unlike send/2, doesnt raise at invalid dest
    token = make_ref()
    GenServer.cast(manager, {:get_pass, token, self(), max_queue_size})
    mon = Process.monitor(manager)

    receive do
      {^token, :pass} ->
        try do
          telemetry_pass_dur(queue_start, manager)

          {:ok, fun.()}
        after
          GenServer.cast(manager, {:done, token})
        end

      {^token, :queue_full} ->
        :queue_full

      {:DOWN, ^mon, :process, _manager, _reason} ->
        :down
    end
  end

  @doc """
  Start the server. Accepted options are the `GenServer` options, and `:max_current` (required) as pos. integer.
  """
  def start_link(opts) do
    {manager_opts, gen_server_opts} = Keyword.split(opts, [:max_current])
    GenServer.start_link(__MODULE__, manager_opts, gen_server_opts)
  end

  @impl true
  def init(init_arg) do
    state = %{
      max_current: Keyword.fetch!(init_arg, :max_current),
      # %{token => monitor}
      current: %{},
      # [{token, monitor, pid}]
      queue: :queue.new(),
      queue_size: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:get_pass, token, reply_to, max_queue_size}, state) do
    cond do
      max_queue_size <= state.queue_size ->
        send(reply_to, {token, :queue_full})
        {:noreply, state}

      map_size(state.current) < state.max_current ->
        mon = Process.monitor(reply_to)
        state = put_in(state.current[token], mon)
        send(reply_to, {token, :pass})

        {:noreply, state}

      true ->
        mon = Process.monitor(reply_to)
        state = update_in(state.queue, &:queue.in({token, mon, reply_to}, &1))
        state = update_in(state.queue_size, &(&1 + 1))
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:done, token}, state) do
    {mon, current} = Map.pop!(state.current, token)
    state = %{state | current: current}
    Process.demonitor(mon, [:flush])

    state = push_if_available(state)

    {:noreply, state}
  end

  # def handle_cast({:cancel, token}, state) do
  #   if token_mon_pid =
  #        Enum.find(state.queue, fn {token_, _, _} -> token === token_ end) do
  #     {_, mon, _} = token_mon_pid
  #     Process.demonitor(mon, [:flush])

  #     queue = List.delete(state.queue, token_mon_pid)
  #     state = %{state | queue: queue, queue_size: state.queue_size - 1}
  #     {:noreply, state}
  #   else
  #     {mon, current} = Map.pop!(state.current, token)
  #     state = %{state | current: current}
  #     Process.demonitor(mon, [:flush])
  #     {:noreply, state}
  #   end
  # end

  @impl true
  def handle_info({:DOWN, ref, :process, _object, _reason}, state) do
    if token =
         Enum.find_value(state.current, fn {token, mon} ->
           if mon == ref, do: token
         end) do
      # Checked-out
      state = update_in(state.current, &Map.delete(&1, token))
      state = push_if_available(state)
      {:noreply, state}
    else
      # In queue
      queue_list = :queue.to_list(state.queue)
      {found, rest} = Enum.split_with(queue_list, fn {_token, mon, _pid} -> mon === ref end)

      state =
        case found do
          [] -> state
          [_] -> update_in(state.queue_size, &(&1 - 1))
        end

      state = %{state | queue: :queue.from_list(rest)}
      {:noreply, state}
    end
  end

  defp push_if_available(state) do
    if map_size(state.current) < state.max_current do
      # There is space
      case :queue.out(state.queue) do
        # but nothing in queue
        {:empty, queue} ->
          %{state | queue: queue}

        # and there is available in queue
        {{:value, {next_token, next_mon, next_pid}}, queue} ->
          state = %{state | queue: queue, queue_size: state.queue_size - 1}

          state = put_in(state.current[next_token], next_mon)

          send(next_pid, {next_token, :pass})

          state
      end
    else
      # There is no space
      state
    end
  end

  defp telemetry_pass_dur(queue_start, manager) do
    dur = monotonic_time() - queue_start

    :telemetry.execute([:ocr_server, :queue_manager_pass], %{duration: dur}, %{
      manager: manager
    })
  end
end
