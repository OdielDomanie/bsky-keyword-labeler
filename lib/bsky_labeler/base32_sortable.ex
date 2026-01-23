defmodule BskyLabeler.Base32Sortable do
  @moduledoc """
  The high-level semantics of a TID are:
  * 64-bit integer
  * big-endian byte ordering
  * encoded as base32-sortable. That is, encoded with characters 234567abcdefghijklmnopqrstuvwxyz
  * no special padding characters (like =) are used, but all digits are always encoded,
    so length is always 13 ASCII characters. The TID corresponding to integer zero is 2222222222222.
  """

  @spec decode(String.t()) :: {:ok, integer()} | {:error, Exception.t()}
  def decode(string) when byte_size(string) == 13 do
    case do_decode(string, 12) do
      {:ok, _} = res ->
        res

      {:error, %ArgumentError{message: msg}} ->
        {:error, %ArgumentError{message: "Invalid base32-sortable: #{inspect(string)}" <> msg}}
    end
  end

  def decode(string) when byte_size(string) != 13 do
    {:error,
     %ArgumentError{message: "Invalid base32-sortable: #{inspect(string)} not 13 characters"}}
  end

  @max_63 2 ** 63

  @spec encode(integer()) :: {:ok, String.t()} | {:error, :not_63_bit_integer}
  def encode(int) when int in 0..(@max_63 - 1)//1 do
    <<
      x00::4,
      x01::5,
      x02::5,
      x03::5,
      x04::5,
      x05::5,
      x06::5,
      x07::5,
      x08::5,
      x09::5,
      x10::5,
      x11::5,
      x12::5
    >> = <<int::64>>

    res =
      [
        value_character(x00),
        value_character(x01),
        value_character(x02),
        value_character(x03),
        value_character(x04),
        value_character(x05),
        value_character(x06),
        value_character(x07),
        value_character(x08),
        value_character(x09),
        value_character(x10),
        value_character(x11),
        value_character(x12)
      ]
      |> List.to_string()

    {:ok, res}
  end

  def encode(int) when is_integer(int) do
    {:error, :not_63_bit_integer}
  end

  defp do_decode(<<c::integer-size(8), rest::binary>>, remaining) when remaining >= 0 do
    # c222222222222 is first bit 1 and the rest 0
    # Despite what the spec says, in reality the first character is b at max
    if remaining == 12 and not (c in ?2..?7 or c in ?a..?b) do
      {:error, %ArgumentError{message: "invalid first character"}}
    else
      with {:ok, val} <- character_value(c),
           {:ok, rest_decoded} <- do_decode(rest, remaining - 1) do
        {:ok, val * 32 ** remaining + rest_decoded}
      end
    end
  end

  defp do_decode(<<>>, -1), do: {:ok, 0}

  defp character_value(c) do
    cond do
      c in ?2..?7 -> {:ok, c - ?2}
      c in ?a..?z -> {:ok, c - ?a + 6}
      true -> {:error, %ArgumentError{message: "invalid character"}}
    end
  end

  defp value_character(val) do
    cond do
      val in 0..5 -> ?2 + val
      val in 6..31 -> ?a + val - 6
    end
  end
end
