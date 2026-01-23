defmodule BskyPoliticsLabeler.TelemetryHandler do
  import BskyPoliticsLabeler.Prometheus

  def attach do
    events = [
      [:uspol, :get_text_http, :stop],
      [:uspol, :get_text_http, :exception],
      [:uspol, :us_politics_analyzing, :stop],
      [:uspol, :us_politics_analyzing, :exception],
      [:uspol, :label],
      [:uspol, :put_label_http, :stop],
      [:uspol, :ws_connect, :ok],
      [:uspol, :ws_connect, :error],
      [:uspol, :ws_closed],
      [:uspol, :ws_terminate_non_shutdown],
      [:uspol, :post_received],
      [:uspol, :post_bad_rkey],
      [:uspol, :post_deleted],
      [:uspol, :post_updated],
      [:uspol, :post_like],
      [:uspol, :post_pass_treshold],
      [:uspol, :post_cant_start_analyze_task],
      [:uspol, :label_tasks]
    ]

    for event <- events do
      handler_id = "prometheus-" <> (event |> tl |> Enum.join("-"))
      :telemetry.attach(handler_id, event, &__MODULE__.handle_event/4, nil)
    end
  end

  def handle_event([:uspol, :get_text_http, :stop], meas, _meta, _config) do
    instrument_get_text_http_duration(meas.duration, "")
  end

  def handle_event([:uspol, :get_text_http, :exception], meas, meta, _) do
    reason =
      case meta.reason do
        {:http_status, status} -> to_string(status)
        _ -> "other"
      end

    instrument_get_text_http_duration(meas.duration, reason)
  end

  def handle_event([:uspol, :us_politics_analyzing, :stop], meas, _, _) do
    instrument_politics_analyzing_duration(meas.duration)
  end

  def handle_event([:uspol, :us_politics_analyzing, :exception], meas, _, _) do
    instrument_politics_analyzing_duration(meas.duration)
  end

  def handle_event([:uspol, :label], _, meta, _) do
    increment_label(meta.pattern)
  end

  def handle_event([:uspol, :put_label_http, :stop], meas, meta, _) do
    reason =
      case meta[:error] do
        nil -> ""
        {:http_status, status} -> to_string(status)
        _ -> "other"
      end

    instrument_put_label_http(meas.duration, reason)
  end

  def handle_event([:uspol, :ws_connect, :ok], _, _, _) do
    increment_ws_connect_ok()
  end

  def handle_event([:uspol, :ws_connect, :error], _, _, _) do
    increment_ws_connect_error("other")
  end

  def handle_event([:uspol, :ws_closed], _, meta, _) do
    reason =
      case meta.reason do
        {:remote, {code, _msg}} -> "remote code: #{code}"
        {:error, reason} -> to_string(reason)
      end

    increment_ws_closed(reason)
  end

  def handle_event([:uspol, :ws_terminate_non_shutdown], _, _, _) do
    increment_ws_terminate_non_shutdown("other")
  end

  def handle_event([:uspol, :post_received], _, _, _) do
    increment_post_received()
  end

  def handle_event([:uspol, :post_bad_rkey], _, _, _) do
    increment_post_bad_rkey()
  end

  def handle_event([:uspol, :post_deleted], _, _, _) do
    increment_post_deleted()
  end

  def handle_event([:uspol, :post_updated], _, _, _) do
    increment_post_updated()
  end

  def handle_event([:uspol, :post_like], _, _, _) do
    increment_post_like()
  end

  def handle_event([:uspol, :post_pass_treshold], _, _, _) do
    increment_post_pass_threshold()
  end

  def handle_event([:uspol, :post_cant_start_analyze_task], _, meta, _) do
    increment_post_cant_start_analyze_task(to_string(meta.reason))
  end

  def handle_event([:uspol, :label_tasks], meas, _, _) do
    track_label_tasks(meas.count)
  end
end
