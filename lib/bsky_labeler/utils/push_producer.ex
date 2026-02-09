defmodule BskyLabeler.Utils.PushProducer do
  @moduledoc """
  A `GenStage` **producer** that can be blockingly pushed events to send upstream.

  Accepts `GenStage` options.
  """
  use GenStage

  @doc """
  Pushes an event to the PushProducer in a blocking manner.

  The push request will be queued until there is enough demand on the
  producer to consume it. This function will block until the PushProducer
  consumes the event.

  If this process exits, the PushProducer will unqueue the request.

  If the PushProducer exits, this function exits.
  """
  def push(push_producer, event) do
    token = GenStage.call(push_producer, :push)
    mon = Process.monitor(push_producer)

    receive do
      {^token, :ready} ->
        GenStage.cast(push_producer, {:push_event, event})
        Process.demonitor(mon, [:flush])
        :ok

      {:DOWN, ^mon, :process, _, reason} ->
        exit({reason, __MODULE__, :push, [push_producer, event]})
    end
  end

  def start_link(opts) do
    GenStage.start_link(__MODULE__, nil, opts)
  end

  @impl GenStage
  def init(_) do
    state = %{
      remaining_demand: 0,
      monitors: %{},
      request_queue: :queue.new()
    }

    {:producer, state, buffer_size: :infinity}
  end

  @impl GenStage
  def handle_call({:push}, {caller, _}, state) do
    if state.remaining_demand > 0 do
      token = make_ref()
      send(caller, {token, :ready})
      {:reply, token, [], state}
    else
      mon = Process.monitor(caller)
      state = update_in(state.monitors, &Map.put(&1, mon, nil))
      state = update_in(state.monitors, &:queue.in({caller, mon}, &1))
      {:reply, mon, [], state}
    end
  end

  @impl GenStage
  def handle_cast({:push_event, event}, state) do
    state = update_in(state.remaining_demand, &max(&1 - 1, 0))
    {:noreply, [event], state}
  end

  @impl GenStage
  def handle_info({:DOWN, mon, :process, _, _}, state) when is_map_key(state.monitors, mon) do
    state = update_in(state.monitors, &Map.delete(&1, mon))
    {:noreply, [], state}
  end

  @impl GenStage
  def handle_demand(demand, state) do
    state = do_handle_demand(demand, state)
    {:noreply, [], state}
  end

  defp do_handle_demand(0 = _demand, state) do
    state
  end

  defp do_handle_demand(demand, state) when demand > 0 do
    case :queue.out(state.request_queue) do
      {:empty, _} ->
        %{state | remaining_demand: state.remaining_demand + demand}

      {{:value, {sender, mon}}, queue} when is_map_key(state.monitors, mon) ->
        Process.demonitor(mon, [:flush])
        monitors = Map.delete(state.monitors, mon)
        remaining_demand = state.remaining_demand + 1
        send(sender, {mon, :ready})

        state = %{
          state
          | request_queue: queue,
            remaining_demand: remaining_demand,
            monitors: monitors
        }

        do_handle_demand(demand - 1, state)

      {{:value, {_sender, _mon}}, queue} ->
        state = %{state | request_queue: queue}
        handle_demand(demand, state)
    end
  end
end
