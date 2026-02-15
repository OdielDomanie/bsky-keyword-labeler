defmodule BskyLabeler.Telemetry do
  use BskyLabeler.Utils.PrometheusTelemetry

  metric(
    name: :bsky_labeler_get_text_http_duration_seconds,
    event: [:bsky_labeler, :get_text_http, :stop],
    type: :histogram,
    help: "HTTP request to get post record execution time",
    labels: [:error],
    buckets: Prometheus.Buckets.new(:default)
  ) do
    %{duration: duration}, metadata ->
      label =
        case metadata[:reason] do
          nil -> ""
          exc when is_exception(exc) -> Exception.message(exc)
          message -> message
        end

      {:observe, duration, [label]}
  end

  metric(
    name: :bsky_labeler_get_text_http_posts_per_fetch_total,
    event: [:bsky_labeler, :get_text_http, :start],
    type: :summary,
    help: "Count of posts fetched per HTTP request"
  ) do
    %{post_count: post_count}, _ -> {:observe, post_count, []}
  end

  metric(
    name: :bsky_labeler_analyzing_duration_seconds,
    event: [:bsky_labeler, :matching],
    type: :histogram,
    help: "Analyze text duration",
    labels: [],
    buckets: [1.0e-5, 1.0e-4, 1.0e-3, 1.0e-2, 1.0e-1, 1.0, :infinity]
  ) do
    %{duration: duration}, _ -> {:observe, duration, []}
  end

  metric(
    name: :bsky_labeler_match_total,
    event: [:bsky_labeler, :label],
    type: :counter,
    help: "Determined matching posts count",
    labels: [:pattern]
  ) do
    _, %{pattern: pattern} -> {:increment, [pattern]}
  end

  metric(
    name: :bsky_labeler_match_component_total,
    event: [:bsky_labeler, :label],
    type: :counter,
    help: "Determined matching posts per component count",
    labels: [:component]
  ) do
    _, %{component: component} -> {:increment, [component]}
  end

  metric(
    name: :bsky_labeler_put_label_http_seconds,
    event: [:bsky_labeler, :put_label_http],
    type: :histogram,
    help: "HTTP request to put label execution time",
    labels: [:error],
    buckets: Prometheus.Buckets.new(:default)
  ) do
    %{duration: duration}, metadata ->
      label =
        case metadata[:error] do
          nil -> ""
          exc when is_exception(exc) -> Exception.message(exc)
          {:http_status, status} -> to_string(status)
        end

      {:observe, duration, [label]}
  end

  metric(
    name: :bsky_labeler_ws_closed_total,
    event: [:bsky_labeler, :ws_closed],
    type: :counter,
    help: "WebSocket closed events count",
    labels: [:reason]
  ) do
    # reason is t:BskyLabeler.Utils.WebsocketProducer.closed_reason/0
    _, %{reason: reason} ->
      reason =
        case reason do
          {:remote, {code, _msg}} -> "remote code: #{code}"
          {:error, reason} -> to_string(reason)
        end

      {:increment, [reason]}
  end

  metric(
    name: :bsky_labeler_post_received_total,
    event: [:bsky_labeler, :post_received],
    type: :counter,
    help: "Posts received from WebSocket count"
  ) do
    _, _ -> {:increment, []}
  end

  metric(
    name: :bsky_labeler_post_bad_rkey_total,
    event: [:bsky_labeler, :post_bad_rkey],
    type: :counter,
    help: "Posts with invalid rkey count"
  ) do
    _, _ -> {:increment, []}
  end

  metric(
    name: :bsky_labeler_post_deleted_total,
    event: [:bsky_labeler, :post_deleted],
    type: :counter,
    help: "Post deletion events count"
  ) do
    _, _ -> {:increment, []}
  end

  metric(
    name: :bsky_labeler_post_updated_total,
    event: [:bsky_labeler, :post_updated],
    type: :counter,
    help: "Post update events count"
  ) do
    _, _ -> {:increment, []}
  end

  metric(
    name: :bsky_labeler_post_like_total,
    event: [:bsky_labeler, :post_like],
    type: :counter,
    help: "Like events for posts count"
  ) do
    _, _ -> {:increment, []}
  end

  metric(
    name: :bsky_labeler_post_pass_threshold_total,
    event: [:bsky_labeler, :post_pass_treshold],
    type: :counter,
    help: "Posts passing like threshold count"
  ) do
    _, _ -> {:increment, []}
  end

  metric(
    name: :bsky_labeler_cursor_difference_seconds,
    event: [:bsky_labeler, :cursor],
    type: :gauge,
    help: "How far back the jetstream cursor is from real time"
  ) do
    %{time_us: time_us}, _ ->
      {:set, System.os_time() - System.convert_time_unit(time_us, :microsecond, :native), []}
  end

  metric(
    name: :bsky_labeler_stage_load,
    event: [:bsky_labeler, :stage_load],
    type: :gauge,
    help: "Approximation of how busy stages are, with values close to 1 indicating a bottleneck",
    labels: [:stage]
  ) do
    %{load: load}, %{stage: stage} ->
      {:set, load, [stage]}
  end
end
