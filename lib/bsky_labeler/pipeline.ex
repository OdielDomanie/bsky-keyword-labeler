defmodule BskyLabeler.Pipeline do
  @moduledoc """
  Supervisor to start the jetstream event analyzing and label-putting pipeline.

  Process is named `BskyLabeler.Pipeline`.

  Options (required):
  * `:min_likes`
  * `:label`
  * `:labeler_did`
  * `:session_manager`
  * `:simulate_emit_event` (optional)

  `BskyLabeler.Patterns` and `BskyLabeler.Repo` are also required to be started.
  """
  alias BskyLabeler.ConfigManager
  alias BskyLabeler.BskyProducer
  alias BskyLabeler.FetchContentStage
  alias BskyLabeler.AnalyzeStage
  alias BskyLabeler.Utils.WebsocketProducer
  use Supervisor

  def start_link(pipeline_opts) do
    Supervisor.start_link(__MODULE__, pipeline_opts, name: __MODULE__)
  end

  @impl Supervisor
  def init(opts) do
    min_likes = Keyword.fetch!(opts, :min_likes)
    label = Keyword.fetch!(opts, :label)
    labeler_did = Keyword.fetch!(opts, :labeler_did)
    session_manager = Keyword.fetch!(opts, :session_manager)

    children = [
      {ConfigManager, min_likes: min_likes, name: ConfigManager},
      {BskyProducer, config_manager: ConfigManager, name: BskyProducer},
      {FetchContentStage.Supervisor,
       subscribe_to_procs: [BskyProducer], count: 2, name: FetchContentStage.Supervisor},
      {AnalyzeStage,
       name: AnalyzeStage,
       label: label,
       labeler_did: labeler_did,
       session_manager: session_manager,
       simulate_emit_event: opts[:simulate_emit_event],
       content_stage_fun: fn ->
         FetchContentStage.Supervisor.workers(FetchContentStage.Supervisor)
       end}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  def bsky_producer_congestion do
    # min_demand 50 max_deman 100 - Two such consumer
    # At max congestion the value will be somewhere between 50 and 100
    WebsocketProducer.buffered_demand(BskyProducer) / 100
  end

  def fetch_content_congestion(timeout \\ 1_000) do
    FetchContentStage.Supervisor.congestion(FetchContentStage.Supervisor, timeout)
  end

  def analyze_congestion do
    AnalyzeStage.congestion(AnalyzeStage, 2)
  end
end
