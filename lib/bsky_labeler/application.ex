defmodule BskyLabeler.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    labeler_did = Application.fetch_env!(:bsky_labeler, :labeler_did)
    labeler_password = Application.fetch_env!(:bsky_labeler, :labeler_password)
    min_likes = Application.get_env(:bsky_labeler, :min_likes)
    regex_file = Application.get_env(:bsky_labeler, :regex_file)

    BskyLabeler.Prometheus.setup()
    BskyLabeler.PrometheusExporter.setup()

    BskyLabeler.TelemetryHandler.attach()

    children = [
      BskyLabeler.Repo,
      BskyLabeler.WebEndpoint,
      {BskyLabeler.Patterns, regex_file},
      {Task.Supervisor, name: BskyLabeler.Label.TaskSV, max_children: 20},
      BskyLabeler.PeriodicMetrics,
      {Atproto.SessionManager,
       name: BskyLabeler.Atproto.SessionManager, did: labeler_did, password: labeler_password}
    ]

    children =
      children ++
        if Application.get_env(:bsky_labeler, :start_websocket) do
          [
            {BskyLabeler.Websocket,
             labeler_did: labeler_did,
             session_manager: BskyLabeler.Atproto.SessionManager,
             min_likes: min_likes}
          ]
        else
          []
        end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :rest_for_one, name: BskyLabeler.Supervisor, max_seconds: 30]
    Supervisor.start_link(children, opts)
  end
end
