defmodule Ocr.Tesseract do
  @doc """
  Returns the OCR'ed text from the image, and the os-process exit code.

  Uses the Tesseract executable given in the `:tesseract_path` application environment,
  which defaults to `"tesseract"`.

  Emits telemetry `[:ocr_server, :tesseract], %{duration: dur}`
  """
  @spec ocr(Enum.t(iodata())) :: {integer(), String}
  def ocr(image_stream) do
    tesseract = Application.get_env(:ocr_server, :tesseract_path, "tesseract")

    start = System.monotonic_time()

    # disable stderr because it sometimes emits errors of tesseract bugs
    {output_data, [{:exit, status_or_epipe}]} =
      Exile.stream([tesseract | ~w(- - -l eng quiet)], input: image_stream, stderr: :disable)
      # "1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n"
      |> Enum.split_while(&is_binary/1)

    telemetry(start)

    {:status, status} = status_or_epipe

    text = IO.iodata_to_binary(output_data)
    {status, text}
  end

  defp telemetry(start) do
    dur = System.monotonic_time() - start

    :telemetry.execute([:ocr_server, :tesseract], %{duration: dur})
  end
end
