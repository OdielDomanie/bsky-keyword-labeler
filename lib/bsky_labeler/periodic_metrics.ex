defmodule BskyLabeler.PeriodicMetrics do
  @moduledoc """
  Emits no telemetry event at regular intervals.
  """

  @interval_ms 1000

  use GenServer, restart: :permanent
  def start_link(_), do: GenServer.start_link(__MODULE__, nil)

  @impl GenServer
  def init(_) do
    {:ok, nil, @interval_ms}
  end

  @impl GenServer
  def handle_info(:timeout, _) do
    {:noreply, nil, @interval_ms}
  end
end
