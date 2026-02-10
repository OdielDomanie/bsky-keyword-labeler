defmodule BskyLabeler.Patterns do
  @moduledoc """
  The process automatically loads regices and returns them on call.

  The process in self-named as `BskyLabeler.Patterns`.

  The only argument is `regex_file`, a string path.

  The file is new-line seperated. Lines starting with `//` and empty lines are
  ignored.

  The file is read everytime the regices are requested and recompiled
  if changed.
  """
  require Logger

  use GenServer

  @spec match(String.t()) :: false | {true, pattern :: String.t()}
  def match(text) do
    Enum.find_value(get_patterns(), false, fn pattern ->
      if text =~ pattern do
        {true, Regex.source(pattern)}
      end
    end)
  end

  @spec get_patterns :: [Regex.t()]
  def get_patterns do
    GenServer.call(__MODULE__, :get_regices)
  end

  def start_link(regex_file) do
    GenServer.start_link(__MODULE__, regex_file, name: __MODULE__)
  end

  @impl GenServer
  def init(regex_file) do
    {:ok, %{path: regex_file, contents: "", regices: []}}
  end

  @impl GenServer
  def handle_call(:get_regices, _, %{contents: contents, regices: regices} = state) do
    new_contents = File.read!(state.path)

    if new_contents == contents do
      {:reply, regices, state}
    else
      new_regices =
        new_contents
        |> String.split("\n")
        |> Enum.reject(&String.starts_with?(&1, "//"))
        |> Enum.reject(&(&1 == ""))
        |> Enum.flat_map(fn pattern_str ->
          # This is PCRE2, u for unicode
          case Regex.compile(pattern_str, "u") do
            {:ok, reg} ->
              [reg]

            {:error, reason} ->
              Logger.error("Regex error: #{inspect(reason)}")
              []
          end
        end)

      Logger.info("Loaded new regices.")
      {:reply, new_regices, %{state | contents: new_contents, regices: new_regices}}
    end
  end
end
