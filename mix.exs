defmodule BskyPoliticsLabeler.MixProject do
  use Mix.Project

  def project do
    [
      app: :bsky_politics_labeler,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :runtime_tools, :os_mon],
      mod: {BskyPoliticsLabeler.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:atproto, git: "https://github.com/OdielDomanie/atproto.git"},
      # {:atproto, path: "../atproto"},
      {:wesex, git: "https://github.com/OdielDomanie/wesex", tag: "0.4.3"},
      {:req, "~> 0.3"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:ecto_psql_extras, "~> 0.7"},
      {:bandit, "~> 1.5"},
      {:telemetry, "~> 1.3"},
      {:prometheus_ex, "~> 5.0"},
      {:plug, "~> 1.19"},
      # For prometheus exporter plug
      {:accept, "~> 0.1"},
      {:stream_data, "~> 1.2", only: [:test]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      test: "test --no-start"
    ]
  end
end
