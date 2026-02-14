defmodule BskyLabeler.PeriodicMetrics do
  @moduledoc """
  Periodically emits telemetry events.

  Events emitted:
        [:bsky_labeler, :stage_congestion],
        %{congestion: congestion},
        %{stage: stage}

  Where stage is one of `:bsky_producer`, `:fetch_content_stage`, `:analyze_stage`.

  The values are a moving average.

  Options are the stages.
  """
  alias BskyLabeler.Pipeline

  @interval_ms 1000
  # Exponential average
  @alpha 0.1

  use GenServer, restart: :permanent
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl GenServer
  def init(opts) do
    avgs = %{
      bsky_producer: 0,
      fetch_content_stage: 0,
      analyze_stage: 0
    }

    Process.send_after(self(), :observe, 0)

    {:ok, {avgs, opts}}
  end

  @impl GenServer
  def handle_info(:observe, {avgs, opts}) do
    avgs =
      for stage <- [:bsky_producer, :fetch_content_stage, :analyze_stage], reduce: avgs do
        avgs ->
          with fc when fc != nil <- opts[stage],
               congestion when congestion != nil <- get_congestion(stage) do
            avgs = update_in(avgs[stage], &(&1 * (1 - @alpha) + congestion * @alpha))

            :telemetry.execute(
              [:bsky_labeler, :stage_congestion],
              %{congestion: avgs[stage]},
              %{stage: stage}
            )

            avgs
          else
            nil ->
              avgs
          end
      end

    Process.send_after(self(), :observe, @interval_ms)

    {:noreply, {avgs, opts}}
  end

  # timeout'ed function can return something later
  def handle_info(_, state) do
    {:noreply, state}
  end

  defp get_congestion(stage) do
    case stage do
      :bsky_producer -> Pipeline.bsky_producer_congestion()
      :fetch_content_stage -> Pipeline.fetch_content_congestion(1_000) || 1.0
      :analyze_stage -> Pipeline.analyze_congestion()
    end
  end
end
