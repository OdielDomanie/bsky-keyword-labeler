defmodule BskyLabeler.TelemetryHandler do
  import BskyLabeler.Prometheus

  def attach do
    events = [
      [:bsky_labeler, :get_text_http, :stop],
      [:bsky_labeler, :get_text_http, :exception],
      [:bsky_labeler, :analyzing, :stop],
      [:bsky_labeler, :analyzing, :exception],
      [:bsky_labeler, :label],
      [:bsky_labeler, :put_label_http, :stop],
      [:bsky_labeler, :ws_connect, :ok],
      [:bsky_labeler, :ws_connect, :error],
      [:bsky_labeler, :ws_closed],
      [:bsky_labeler, :ws_terminate_non_shutdown],
      [:bsky_labeler, :post_received],
      [:bsky_labeler, :post_bad_rkey],
      [:bsky_labeler, :post_deleted],
      [:bsky_labeler, :post_updated],
      [:bsky_labeler, :post_like],
      [:bsky_labeler, :post_pass_treshold],
      [:bsky_labeler, :post_cant_start_analyze_task],
      [:bsky_labeler, :label_tasks]
    ]

    for event <- events do
      handler_id = "prometheus-" <> (event |> tl |> Enum.join("-"))
      :telemetry.attach(handler_id, event, &__MODULE__.handle_event/4, nil)
    end
  end

  def handle_event([:bsky_labeler, :get_text_http, :stop], meas, _meta, _config) do
    instrument_get_text_http_duration(meas.duration, "")
  end

  def handle_event([:bsky_labeler, :get_text_http, :exception], meas, meta, _) do
    reason =
      case meta.reason do
        {:http_status, status} -> to_string(status)
        _ -> "other"
      end

    instrument_get_text_http_duration(meas.duration, reason)
  end

  def handle_event([:bsky_labeler, :analyzing, :stop], meas, _, _) do
    instrument_analyzing_duration(meas.duration)
  end

  def handle_event([:bsky_labeler, :analyzing, :exception], meas, _, _) do
    instrument_analyzing_duration(meas.duration)
  end

  def handle_event([:bsky_labeler, :label], _, meta, _) do
    increment_label(meta.pattern)
    increment_label_component(meta.component)
  end

  def handle_event([:bsky_labeler, :put_label_http, :stop], meas, meta, _) do
    reason =
      case meta[:error] do
        nil -> ""
        {:http_status, status} -> to_string(status)
        _ -> "other"
      end

    instrument_put_label_http(meas.duration, reason)
  end

  def handle_event([:bsky_labeler, :ws_connect, :ok], _, _, _) do
    increment_ws_connect_ok()
  end

  def handle_event([:bsky_labeler, :ws_connect, :error], _, _, _) do
    increment_ws_connect_error("other")
  end

  def handle_event([:bsky_labeler, :ws_closed], _, meta, _) do
    reason =
      case meta.reason do
        {:remote, {code, _msg}} -> "remote code: #{code}"
        {:error, reason} -> to_string(reason)
      end

    increment_ws_closed(reason)
  end

  def handle_event([:bsky_labeler, :ws_terminate_non_shutdown], _, _, _) do
    increment_ws_terminate_non_shutdown("other")
  end

  def handle_event([:bsky_labeler, :post_received], _, _, _) do
    increment_post_received()
  end

  def handle_event([:bsky_labeler, :post_bad_rkey], _, _, _) do
    increment_post_bad_rkey()
  end

  def handle_event([:bsky_labeler, :post_deleted], _, _, _) do
    increment_post_deleted()
  end

  def handle_event([:bsky_labeler, :post_updated], _, _, _) do
    increment_post_updated()
  end

  def handle_event([:bsky_labeler, :post_like], _, _, _) do
    increment_post_like()
  end

  def handle_event([:bsky_labeler, :post_pass_treshold], _, _, _) do
    increment_post_pass_threshold()
  end

  def handle_event([:bsky_labeler, :post_cant_start_analyze_task], _, meta, _) do
    increment_post_cant_start_analyze_task(to_string(meta.reason))
  end

  def handle_event([:bsky_labeler, :label_tasks], meas, _, _) do
    track_label_tasks(meas.count)
  end
end
