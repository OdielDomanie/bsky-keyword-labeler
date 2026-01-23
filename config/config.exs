import Config

config :bsky_labeler,
  ecto_repos: [BskyLabeler.Repo]

# config :logger,
#   level: :info

config :logger,
  compile_time_purge_matching: [
    [application: :req, level_lower_than: :error]
    # [module: Bar, function: "foo/3", ]
  ]

config :bsky_labeler, BskyLabeler.WebEndpoint,
  url: [host: "localhost"],
  server: true,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: BskyLabeler.WebEndpoint.ErrorHTML],
    layout: false
  ],
  live_view: [signing_salt: "jWkfqfmF"]

import_config "#{config_env()}.exs"
