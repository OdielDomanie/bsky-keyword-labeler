defmodule BskyLabeler.Patterns do
  @moduledoc """
  The process automatically loads regices and returns them on call.

  The process in self-named as `BskyLabeler.Patterns`.

  The only argument is `regex_file`, a string path.

  The file is new-line seperated. Lines starting with `//` and empty lines are
  ignored.

  A line can have multiple regices seperated by "` && `" (with spaces).
  A match is only made if all the regices in the line match.

  The file is read everytime the regices are requested and recompiled
  if changed. If a regex is invalid, that line is skipped and an error
  is logged.
  """
  require Logger

  use GenServer

  @spec match(String.t()) :: false | {true, pattern :: String.t()}
  def match(text) do
    Enum.find_value(get_patterns(), false, fn patterns ->
      {:regices_and, regices} = patterns
      false = Enum.empty?(regices)

      if Enum.all?(regices, fn regex -> text =~ regex end) do
        {true, regices |> Enum.map(&Regex.source/1) |> Enum.join(" && ")}
      end
    end)
  end

  @spec get_patterns :: [{:regices_and, [Regex.t()]}]
  def get_patterns do
    GenServer.call(__MODULE__, :get_patterns)
  end

  def start_link(regex_file) do
    GenServer.start_link(__MODULE__, regex_file, name: __MODULE__)
  end

  @impl GenServer
  def init(regex_file) do
    {:ok, %{path: regex_file, contents: "", patterns: []}}
  end

  @impl GenServer
  def handle_call(:get_patterns, _, %{contents: contents, patterns: patterns} = state) do
    new_contents = File.read!(state.path)

    if new_contents == contents do
      {:reply, patterns, state}
    else
      new_patterns =
        new_contents
        |> String.split("\n")
        |> Enum.reject(&String.starts_with?(&1, "//"))
        |> Enum.reject(&(&1 == ""))
        |> Enum.flat_map(&line_to_patterns/1)

      Logger.info("Loaded new patterns.")
      {:reply, new_patterns, %{state | contents: new_contents, patterns: new_patterns}}
    end
  end

  defp line_to_patterns(line) do
    str_clauses = String.split(line, " && ") |> Enum.reject(&(&1 == ""))

    result = do_str_to_patterns(str_clauses)

    case result do
      [{:regices_and, []}] ->
        Logger.error("Regex error: bad \" && \ seperation")
        []

      [] ->
        []

      [{:regices_and, _}] ->
        result
    end
  end

  defp do_str_to_patterns([]) do
    [{:regices_and, []}]
  end

  defp do_str_to_patterns([str_clause | rest]) do
    # This is PCRE2, u for unicode
    case Regex.compile(str_clause, "u") do
      {:ok, reg} ->
        case do_str_to_patterns(rest) do
          [{:regices_and, clauses}] ->
            [{:regices_and, [reg | clauses]}]

          [] ->
            []
        end

      {:error, reason} ->
        Logger.error("Regex error: #{inspect(reason)}")
        []
    end
  end
end
