defmodule BskyLabeler.Prometheus do
  require Logger
  use Prometheus

  def setup do
    # Summary.declare(
    :prometheus_quantile_summary.declare(
      name: :bsky_labeler_get_text_http_duration_seconds,
      help: "HTTP request to get post record execution time",
      labels: [:error]
    )

    :prometheus_quantile_summary.declare(
      name: :bsky_labeler_analyzing_duration_seconds,
      help: "Time takes to analyze text execution time"
    )

    Counter.declare(
      name: :bsky_labeler_match_total,
      help: "Determined matching posts count",
      labels: [:pattern]
    )

    Counter.declare(
      name: :bsky_labeler_match_component_total,
      help: "Determined matching posts per component count",
      labels: [:component]
    )

    :prometheus_quantile_summary.declare(
      name: :bsky_labeler_put_label_http_seconds,
      help: "HTTP request to put label execution time",
      labels: [:error]
    )

    # WebSocket connection metrics
    Counter.declare(
      name: :bsky_labeler_ws_connect_ok_total,
      help: "Successful WebSocket connections count"
    )

    Counter.declare(
      name: :bsky_labeler_ws_connect_error_total,
      help: "Failed WebSocket connection attempts count",
      labels: [:error]
    )

    Counter.declare(
      name: :bsky_labeler_ws_closed_total,
      help: "WebSocket closed events count",
      labels: [:reason]
    )

    Counter.declare(
      name: :bsky_labeler_ws_terminate_non_shutdown_total,
      help: "WebSocket non-shutdown terminations count",
      labels: [:reason]
    )

    # Post event metrics
    Counter.declare(
      name: :bsky_labeler_post_received_total,
      help: "Posts received from WebSocket count"
    )

    Counter.declare(
      name: :bsky_labeler_post_bad_rkey_total,
      help: "Posts with invalid rkey count"
    )

    Counter.declare(
      name: :bsky_labeler_post_deleted_total,
      help: "Post deletion events count"
    )

    Counter.declare(
      name: :bsky_labeler_post_updated_total,
      help: "Post update events count"
    )

    Counter.declare(
      name: :bsky_labeler_post_like_total,
      help: "Like events for posts count"
    )

    Counter.declare(
      name: :bsky_labeler_post_pass_threshold_total,
      help: "Posts passing like threshold count"
    )

    Counter.declare(
      name: :bsky_labeler_post_cant_start_analyze_task_total,
      help: "Failed task starts for analysis count",
      labels: [:reason]
    )

    ##

    Gauge.declare(name: :bsky_labeler_label_tasks, help: "Active labeling tasks count")
  end

  def instrument_get_text_http_duration(time_native, error) do
    # Summary.observe(
    :prometheus_quantile_summary.observe(
      :bsky_labeler_get_text_http_duration_seconds,
      [error],
      # convert_to_s(time_native)
      time_native
    )
  end

  def instrument_analyzing_duration(time_native) do
    # Since seconds in name, the library automagically converts native to seconds :(
    :prometheus_quantile_summary.observe(
      :bsky_labeler_analyzing_duration_seconds,
      time_native
    )
  end

  def increment_label(pattern) do
    Counter.inc(
      name: :bsky_labeler_match_total,
      labels: [pattern]
    )
  end

  def increment_label_component(component) do
    Counter.inc(
      name: :bsky_labeler_match_component_total,
      labels: [component]
    )
  end

  def instrument_put_label_http(time_native, error) do
    :prometheus_quantile_summary.observe(
      :bsky_labeler_put_label_http_seconds,
      [error],
      convert_to_s(time_native)
    )
  end

  # WebSocket instrumentation functions
  def increment_ws_connect_ok do
    Counter.inc(name: :bsky_labeler_ws_connect_ok_total)
  end

  def increment_ws_connect_error(error) do
    Counter.inc(
      name: :bsky_labeler_ws_connect_error_total,
      labels: [error]
    )
  end

  def increment_ws_closed(reason) do
    Counter.inc(
      name: :bsky_labeler_ws_closed_total,
      labels: [reason]
    )
  end

  def increment_ws_terminate_non_shutdown(reason) do
    Counter.inc(
      name: :bsky_labeler_ws_terminate_non_shutdown_total,
      labels: [reason]
    )
  end

  def increment_post_received do
    Counter.inc(name: :bsky_labeler_post_received_total)
  end

  def increment_post_bad_rkey do
    Counter.inc(name: :bsky_labeler_post_bad_rkey_total)
  end

  def increment_post_deleted do
    Counter.inc(name: :bsky_labeler_post_deleted_total)
  end

  def increment_post_updated do
    Counter.inc(name: :bsky_labeler_post_updated_total)
  end

  def increment_post_like do
    Counter.inc(name: :bsky_labeler_post_like_total)
  end

  def increment_post_pass_threshold do
    Counter.inc(name: :bsky_labeler_post_pass_threshold_total)
  end

  def increment_post_cant_start_analyze_task(reason) do
    Counter.inc(
      name: :bsky_labeler_post_cant_start_analyze_task_total,
      labels: [reason]
    )
  end

  def track_label_tasks(count) do
    Gauge.set([name: :bsky_labeler_label_tasks], count)
  end

  defp convert_to_s(native) do
    factor = System.convert_time_unit(1, :second, :native)
    native / factor
  end
end
