defmodule BskyLabeler.Base32SortableTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias BskyLabeler.Base32Sortable

  test "Corresponding to integer zero is 2222222222222" do
    assert {:ok, 0} === Base32Sortable.decode("2222222222222")
  end

  test "Converts some modern time" do
    assert {:ok, 1_792_264_486_591_488_002} == Base32Sortable.decode("3lrvb3s3hes24")
  end

  test "Encodes zero" do
    assert {:ok, "2222222222222"} == Base32Sortable.encode(0)
  end

  test "Encodes some modern time" do
    assert {:ok, "3lrvb3s3hes24"} == Base32Sortable.encode(1_792_264_486_591_488_002)
  end

  test "Returns error when encoding bad int" do
    assert {:error, _} = Base32Sortable.encode(15_430_336_435_956_328_567)
  end

  test "Returns error when decoding bad str" do
    assert {:error, _} = Base32Sortable.decode("jlrvb3s3hes24")
  end

  test "Returns error when encoding bad int (2)" do
    assert {:error, _} = Base32Sortable.encode(17_933_165_551_087_345_666)
  end

  def decoded_gen() do
    gen all <<int_rest::63>> <- bitstring(length: 63) do
      <<int::64>> = <<0::1, int_rest::63>>
      int
    end
  end

  def encoded_gen() do
    gen all first_char <- string(Enum.concat([?2..?7, ?a..?b]), length: 1),
            rest <- string(Enum.concat([?2..?7, ?a..?z]), length: 12),
            str = first_char <> rest do
      str
    end

    # gen all <<int_rest::63>> <- bitstring(length: 63) do
    #   <<int::64>> = <<0::1, int_rest::63>>
    #   {:ok, enc} = Base32Sortable.encode(int)
    #   enc
    # end
  end

  property "decoded is 64-bit u-integer" do
    check all encoded <- encoded_gen() do
      {:ok, dec} = Base32Sortable.decode(encoded)

      assert dec >= 0
      assert dec < 2 ** 64
    end
  end

  property "decoded top bit always zero" do
    check all encoded <- encoded_gen() do
      {:ok, dec} = Base32Sortable.decode(encoded)

      assert <<0::1, rest::63>> = <<dec::64>>, inspect(dec)
      assert rest == dec
    end
  end

  property "encoded with certain characters" do
    check all decoded <- decoded_gen() do
      {:ok, enc} = Base32Sortable.encode(decoded)

      chars = ~c"234567abcdefghijklmnopqrstuvwxyz"

      assert enc |> String.to_charlist() |> Enum.all?(&(&1 in chars))
    end
  end

  property "encoded with 13 characters" do
    check all decoded <- decoded_gen() do
      {:ok, enc} = Base32Sortable.encode(decoded)

      assert String.length(enc) == 13
    end
  end

  property "encoded start with certain characters" do
    check all decoded <- decoded_gen() do
      {:ok, enc} = Base32Sortable.encode(decoded)

      valid = "234567abcdefghij"

      first = String.first(enc)
      assert String.contains?(valid, first)
    end
  end

  property "decode -> encode roundtrip" do
    check all gen_encoded <- encoded_gen() do
      {:ok, dec} = Base32Sortable.decode(gen_encoded)
      {:ok, enc} = Base32Sortable.encode(dec)

      assert enc === gen_encoded
    end
  end

  def bad_decoded_gen() do
    bad_64 =
      gen all <<int_rest::63>> <- bitstring(length: 63) do
        <<int::64>> = <<1::1, int_rest::63>>
        int
      end

    # gen all bit_size <- non_negative_integer(),
    #         bit_size = bit_size ++ 65,
    #         <<int::bit_size>> = bitstring <- bitstring(length: bit_size) do
    #   int
    non_64 =
      gen all int <- non_negative_integer() do
        int + 2 ** 63
      end

    one_of([bad_64, non_64])
  end

  def bad_encoded_gen() do
    random_str =
      string(:utf8)
      |> filter(fn str ->
        not (str =~ ~r/^[234567ab][234567abcdefghijklmnopqrstuvwxyz]{12}$/)
      end)

    too_large_str =
      gen all first_char <- string([?c..?j], length: 1),
              rest <- string(Enum.concat([?2..?7, ?a..?z]), length: 12),
              str = first_char <> rest do
        str
      end

    one_of([random_str, too_large_str])
  end

  property "bad decoding returns error" do
    check all enc <- bad_encoded_gen() do
      assert {:error, %ArgumentError{}} = Base32Sortable.decode(enc)
    end
  end

  property "bad encoding returns error" do
    check all dec <- bad_decoded_gen() do
      assert {:error, _} = Base32Sortable.encode(dec)
    end
  end
end
