defmodule BskyPoliticsLabeler.PeriodicMetrics do
  @moduledoc """
  Emits `[:uspol, :label_tasks]` telemetry event at regular intervals.
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
    count = Task.Supervisor.children(BskyPoliticsLabeler.Label.TaskSV) |> Enum.count()
    :telemetry.execute([:uspol, :label_tasks], %{count: count})

    {:noreply, nil, @interval_ms}
  end
end
