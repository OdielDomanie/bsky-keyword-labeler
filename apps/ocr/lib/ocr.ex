defmodule Ocr do
  alias Ocr.Tesseract
  alias Ocr.QueueManager

  @ocr_queue_manager Ocr.QueueManager

  @spec ocr_from_urls(node(), [URI.t() | String.t()], pos_integer()) ::
          {:ok, [{:ok, String.t() | :queue_full}]}
          | {:error, :noconnection | :system_limit | {:fetch_error, Exception.t()}}
  def ocr_from_urls(node, image_urls, max_queue) do
    try do
      res =
        :erpc.call(node, __MODULE__, :ocr_from_urls, [image_urls, max_queue], %{
          always_spawn: true,
          timeout: :infinity
        })

      {:ok, res}
    catch
      :error, {:erpc, erpc_error_reason}
      when erpc_error_reason in [:noconnection, :system_limit] ->
        {:error, erpc_error_reason}
    end
  end

  def ocr_from_urls([], _max_queue) do
    []
  end

  def ocr_from_urls([image_url | rest], max_queue) do
    case fetch_image(image_url) do
      {:ok, image_stream} ->
        QueueManager.command(
          @ocr_queue_manager,
          fn ->
            {os_exit, text} = Tesseract.ocr(image_stream)
            # If tesseract is erroring it is likely not a sporadic error
            0 = os_exit
            text
          end,
          max_queue
        )
        |> case do
          {:ok, result} -> [{:ok, result} | ocr_from_urls(rest, max_queue)]
          reason -> [{reason, length(rest)}]
        end

      reason ->
        [{reason, length(rest) + 1}]
    end
  end

  defp fetch_image(url) do
    case Req.get(url) do
      {:ok, %Req.Response{body: image, status: 200}} ->
        {:ok, [image]}

      {:ok, %Req.Response{body: body, status: status}} ->
        {:error, %RuntimeError{message: "URL #{url} status: #{status} body: #{inspect(body)}"}}

      {:error, _} = error ->
        error
    end
  end
end
