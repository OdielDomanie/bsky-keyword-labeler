defmodule BskyLabeler.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    labeler_did = Application.fetch_env!(:bsky_labeler, :labeler_did)
    labeler_password = Application.fetch_env!(:bsky_labeler, :labeler_password)
    label = Application.fetch_env!(:bsky_labeler, :label)
    min_likes = Application.get_env(:bsky_labeler, :min_likes)
    regex_file = Application.get_env(:bsky_labeler, :regex_file)
    post_retain_secs = Application.get_env(:bsky_labeler, :post_retain_secs)

    simulate_emit_event = Application.get_env(:bsky_labeler, :simulate_emit_event)

    BskyLabeler.Telemetry.setup_prometheus()
    BskyLabeler.Utils.PrometheusExporter.setup()
    BskyLabeler.Telemetry.attach_telemetry()

    pipeline =
      if Application.get_env(:bsky_labeler, :start_websocket) do
        [
          {BskyLabeler.Pipeline,
           min_likes: min_likes,
           label: label,
           labeler_did: labeler_did,
           session_manager: BskyLabeler.Atproto.SessionManager,
           simulate_emit_event: simulate_emit_event}
        ]
      else
        []
      end

    children =
      [
        BskyLabeler.Repo,
        BskyLabeler.WebEndpoint,
        {BskyLabeler.Patterns, regex_file},
        {Atproto.SessionManager,
         name: BskyLabeler.Atproto.SessionManager, did: labeler_did, password: labeler_password}
      ] ++
        pipeline ++
        [
          {BskyLabeler.Application.Extra, post_retain_secs: post_retain_secs}
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :rest_for_one, name: BskyLabeler.Supervisor, max_seconds: 30]
    Supervisor.start_link(children, opts)
  end
end

defmodule BskyLabeler.Application.Extra do
  @moduledoc false
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts)
  end

  @impl Supervisor
  def init(opts) do
    periodic_metrics =
      if Application.get_env(:bsky_labeler, :start_websocket) do
        [
          {BskyLabeler.PeriodicMetrics,
           periodic_metrics_opts() ++ [name: BskyLabeler.PeriodicMetrics]}
        ]
      else
        []
      end

    Supervisor.init(
      periodic_metrics ++
        [
          {BskyLabeler.PostDbCleaner, opts[:post_retain_secs]}
        ],
      strategy: :one_for_one
    )
  end

  defp periodic_metrics_opts do
    [
      bsky_producer: BskyLabeler.BskyProducer,
      fetch_content_stage: BskyLabeler.FetchContentStage.Supervisor,
      analyze_stage: BskyLabeler.AnalyzeStage
    ]
  end
end
