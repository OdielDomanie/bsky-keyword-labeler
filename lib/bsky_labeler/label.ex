defmodule BskyLabeler.Label do
  require Logger
  alias BskyLabeler.{Base32Sortable, BskyHttpApi, Post, Patterns}
  import System, only: [system_time: 0, monotonic_time: 0]

  def label(post, subject_cid, labeler_did, session_manager) do
    texts = BskyHttpApi.get_text(post)

    # TELEMETRY
    nomatch_or_reason =
      :telemetry.span([:bsky_labeler, :analyzing], %{}, fn ->
        res =
          Patterns.match(texts.text) ||
            Enum.find_value(texts.alts, false, fn alt -> Patterns.match(alt || "") end) ||
            Patterns.match(texts.embed_title || "") ||
            Patterns.match(texts.embed_desc || "")

        {res, %{}}
      end)

    case nomatch_or_reason do
      {true, pattern} ->
        # TELEMETRY
        :telemetry.execute([:bsky_labeler, :label], %{system_time: system_time()}, %{
          pattern: pattern
        })

        Logger.debug("#{true}, #{pattern}: #{inspect(texts)}")

        if not Application.get_env(:bsky_labeler, :simulate_emit_event) do
          put_label(post, pattern, subject_cid, labeler_did, session_manager)
        end

      false ->
        Logger.debug("#{false}: #{inspect(texts)}")
    end
  end

  def put_label(
        %Post{did: subject_did, rkey: subject_rkey},
        reason,
        subject_cid,
        labeler_did,
        session_manager
      ) do
    {:ok, subject_rkey} = Base32Sortable.encode(subject_rkey)

    subject_uri = "at://#{subject_did}/app.bsky.feed.post/#{subject_rkey}"

    path = "/xrpc/tools.ozone.moderation.emitEvent"
    method = :post

    label = Application.get_env(:bsky_labeler, :label)
    true = to_string(label) != ""

    body = %{
      event: %{
        "$type": "tools.ozone.moderation.defs#modEventLabel",
        comment: reason,
        createLabelVals: [label],
        negateLabelVals: []
        #  durationInHours: 0
      },
      subject: %{
        "$type": "com.atproto.repo.strongRef",
        uri: subject_uri,
        cid: subject_cid
      },
      createdBy: labeler_did
    }

    # TELEMETRY
    start_measurements = %{system_time: system_time(), monotonic_time: monotonic_time()}
    ctx = make_ref()
    :telemetry.execute([:bsky_labeler, :put_label_http, :start], start_measurements, %{ctx: ctx})

    case Atproto.request([url: path, json: body, method: method], session_manager)
         |> Req.merge(
           headers: [
             "atproto-proxy": labeler_did <> "#atproto_labeler",
             "accept-language": "en-US"
           ]
         )
         |> Req.request() do
      {:ok, %Req.Response{status: 200, body: body}} ->
        # Logger.info("Put labeler service record: #{inspect(body)}")
        stop_measurements = %{
          duration: monotonic_time() - start_measurements.monotonic_time,
          monotonic_time: start_measurements.monotonic_time
        }

        :telemetry.execute([:bsky_labeler, :put_label_http, :stop], stop_measurements, %{ctx: ctx})

        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} when status >= 400 ->
        stop_measurements = %{
          duration: monotonic_time() - start_measurements.monotonic_time,
          monotonic_time: start_measurements.monotonic_time
        }

        :telemetry.execute([:bsky_labeler, :put_label_http, :stop], stop_measurements, %{
          ctx: ctx,
          error: {:http_status, status}
        })

        {:error,
         %RuntimeError{
           message: """
           The requested URL returned error: #{status}
           Response body: #{inspect(body)}\
           """
         }}

      {:error, reason} = err ->
        stop_measurements = %{
          duration: monotonic_time() - start_measurements.monotonic_time,
          monotonic_time: start_measurements.monotonic_time
        }

        :telemetry.execute([:bsky_labeler, :put_label_http, :stop], stop_measurements, %{
          ctx: ctx,
          error: reason
        })

        err
    end
  end
end
