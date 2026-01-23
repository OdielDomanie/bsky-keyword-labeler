defmodule BskyPoliticsLabeler.PrometheusExporter do
  # Adapted from https://github.com/prometheus-erl/prometheus-plugs/blob/v1.1.5/lib/prometheus/plug_exporter.ex
  # Original under MIT license, Copyright (c) 2016-, Ilya Khaprov.

  @moduledoc """
  Exports Prometheus metrics via configurable endpoint:

  ``` elixir
  # on app startup (e.g. supervisor setup)
  MetricsPlugExporter.setup()

  # in your plugs pipeline
  plug MetricsPlugExporter
  ```
  ### Metrics

  Also maintains telemetry metrics:
  - telemetry_scrape_duration_seconds
  - telemetry_scrape_size_bytes

  Do not forget to call `setup/0` before using plug, for example on application start!
  """

  require Logger

  use Prometheus.Metric

  @format :auto

  import Plug.Conn
  use Prometheus.Metric

  def setup do
    Summary.declare(
      name: :telemetry_scrape_duration_seconds,
      help: "Scrape duration",
      labels: ["content_type"]
    )

    Summary.declare(
      name: :telemetry_scrape_size_bytes,
      help: "Scrape size, uncompressed",
      labels: ["content_type"]
    )
  end

  use Plug.Builder

  plug :auth
  plug :send_metrics

  defp auth(conn, _opts) do
    password = Application.fetch_env!(:bsky_politics_labeler, :prometheus_password)
    if to_string(password) == "", do: raise("Prometheus password is empty")
    Plug.BasicAuth.basic_auth(conn, username: "admin", password: password)
  end

  defp send_metrics(conn, _opts) do
    {content_type, scrape} = scrape_data(conn)

    conn
    |> put_resp_content_type(content_type, nil)
    |> send_resp(200, scrape)
    |> halt
  end

  defp scrape_data(conn) do
    {content_type, format} = negotiate(conn)
    labels = [content_type]

    scrape =
      Summary.observe_duration(
        [
          name: :telemetry_scrape_duration_seconds,
          labels: labels
        ],
        fn ->
          format.format()
        end
      )

    Summary.observe(
      [name: :telemetry_scrape_size_bytes, labels: labels],
      :erlang.iolist_size(scrape)
    )

    {content_type, scrape}
  end

  defp negotiate(conn, format \\ @format) do
    format = normalize_format(format)

    if format == :auto do
      try do
        [accept] = Plug.Conn.get_req_header(conn, "accept")

        format =
          :accept_header.negotiate(
            accept,
            [
              {:prometheus_protobuf_format.content_type(), :prometheus_protobuf_format},
              {:prometheus_text_format.content_type(), :prometheus_text_format}
            ]
          )

        {format.content_type(), format}
      rescue
        ErlangError ->
          {:prometheus_text_format.content_type(), :prometheus_text_format}
      end
    else
      {format.content_type(), format}
    end
  end

  defp normalize_format(:auto), do: :auto
  defp normalize_format(:text), do: :prometheus_text_format
  defp normalize_format(:protobuf), do: :prometheus_protobuf_format
  defp normalize_format(Prometheus.Format.Text), do: :prometheus_text_format
  defp normalize_format(Prometheus.Format.Protobuf), do: :prometheus_protobuf_format
  defp normalize_format(format), do: format
end
