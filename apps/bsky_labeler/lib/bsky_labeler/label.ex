defmodule BskyLabeler.Label do
  @moduledoc """
  About atproto labels.
  """
  import System, only: [monotonic_time: 0]
  require Logger

  @doc """
  Emits a label event.

  Returns decoded response on success; otherwise the exception.
  Raises on 4xx status.
  """
  @spec put_label(
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          Atproto.SessionManager.session_manager()
        ) :: {
          {:ok, map()} | {:error, Exception.t()}
        }
  def put_label(at_uri, cid, label, reason, labeler_did, session_manager) do
    path = "/xrpc/tools.ozone.moderation.emitEvent"
    method = :post

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
        uri: at_uri,
        cid: cid
      },
      createdBy: labeler_did
    }

    timer = monotonic_time()

    Atproto.request([url: path, json: body, method: method], session_manager)
    |> Req.merge(
      headers: [
        "atproto-proxy": labeler_did <> "#atproto_labeler",
        "accept-language": "en-US"
      ]
    )
    |> Req.request()
    |> case do
      {:ok, %Req.Response{status: 200, body: body}} ->
        telem_put_label(timer)
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} when status >= 500 or status === 408 ->
        telem_put_label(timer, {:http_status, status})

        {:error,
         %RuntimeError{
           message: """
           The requested URL returned error: #{status}
           Response body: #{inspect(body)}\
           """
         }}

      {:ok, %Req.Response{status: status, body: body}} ->
        telem_put_label(timer, {:http_status, status})

        # If status 4xx or otherwise non-500 or 200, this will happen everytime,
        # so do crash, except 408 Request Timeout, which sometimes happens?
        raise """
        The requested URL returned error: #{status}
        Response body: #{inspect(body)}\
        """

      {:error, reason} = err ->
        telem_put_label(timer, reason)
        err
    end
  end

  # error can be {:http_status, status}, or an exception
  defp telem_put_label(start, error \\ nil) do
    measurements = %{duration: monotonic_time() - start}
    metadata = %{error: error}

    :telemetry.execute([:bsky_labeler, :put_label_http], measurements, metadata)
  end
end
