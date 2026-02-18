defmodule Ocr.MixProject do
  use Mix.Project

  def project do
    [
      app: :ocr,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Ocr.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:exile, "~> 0.13"},
      {:telemetry, "~> 1.3"},
      {:req, "~> 0.3"}
    ]
  end
end
