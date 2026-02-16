defmodule BskyLabeler.AnalyzeStage do
  @moduledoc """
  A `ConsumerSupervisor` that analyzes posts and labels them.

  Childspec options:
  * `:content_stage_fun` — (required) A function the returns a list of
      processes to subscribe to.
  * `:label` — (required) The registered label id to label the posts with.
  * `:labeler_did` — (required) The DID of the labeler to label on behalf of.
  * `:session_manager` — (required) The `Atproto.SessionManager` associated with the labeler DID.
  * `:simulate_emit_event`

  `BskyLabeler.Patterns` is also required to be started.

  This stage consumes "post data" events as emitted by `BskyLabeler.FetchContentStage`.

  The post is checked against the regices. If no match, then OCR'ed possible
  and the OCR'ed text is checked against the regices.
  If any matches, the label is posted.
  """
  use ConsumerSupervisor

  defp max_demand_default do
    System.schedulers_online() + 1
  end

  @doc """
  Gets a value between 0 and 1 representing how congested the stage is.
  """
  def get_load(sv, producer_count) do
    ConsumerSupervisor.count_children(sv).active / (max_demand_default() * producer_count)
  end

  def start_link(opts) do
    {ms_opts, cs_opts} =
      Keyword.split(opts, [
        :content_stage_fun,
        :label,
        :labeler_did,
        :session_manager,
        :simulate_emit_event
      ])

    ConsumerSupervisor.start_link(__MODULE__, ms_opts, cs_opts)
  end

  @impl ConsumerSupervisor
  def init(opts) do
    content_stage_fun = Keyword.fetch!(opts, :content_stage_fun)

    config = %{
      label: Keyword.fetch!(opts, :label),
      labeler_did: Keyword.fetch!(opts, :labeler_did),
      session_manager: Keyword.fetch!(opts, :session_manager),
      simulate_emit_event: opts[:simulate_emit_event]
    }

    subscribe_to =
      for stage <- content_stage_fun.() do
        max_demand = opts[:max_demand] || max_demand_default()
        min_demand = opts[:min_demand] || max_demand - 1
        {stage, min_demand: min_demand, max_demand: max_demand}
      end

    children = [{BskyLabeler.AnalyzeStage.Task, config}]
    opts = [strategy: :one_for_one, subscribe_to: subscribe_to]
    ConsumerSupervisor.init(children, opts)
  end
end

defmodule BskyLabeler.AnalyzeStage.Task do
  @moduledoc false
  alias BskyLabeler.{Label, Patterns}
  require Logger

  use Task, restart: :temporary

  def start_link(config, event) do
    Task.start_link(__MODULE__, :run, [event, config])
  end

  def run(post_data, config) do
    case pattern_match(post_data, config) do
      {:ok, component, pattern, str} ->
        Logger.debug("match, #{component} #{pattern}: #{str}")

        if String.contains?(pattern, "&&") do
          Logger.warning("match, #{component} #{pattern}: #{str}")
        end

        telem_label(component, pattern)

        if !config[:simulate_emit_event] do
          put_label(post_data, component, pattern, config)
        end

      false ->
        # Logger.debug("#{false}: #{inspect(post_data["record"])}")
        # Logger.debug("no match")

        # TODO! OCR
        nil
    end
  end

  defp pattern_match(post_data, _config) do
    %{
      "record" => %{
        "text" => text
      }
    } = post_data

    images = post_data["record"]["embed"]["images"] || []

    alts =
      for %{"alt" => alt} <- images, alt != "" do
        alt
      end

    embed_title = post_data["embed"]["external"]["title"]
    embed_description = post_data["embed"]["external"]["description"]

    timer = System.monotonic_time()

    # Required BskyLabeler.Patterns to be started (it is self-named)
    cond do
      pat = Patterns.match(text) ->
        {:ok, :text, elem(pat, 1), text}

      pat = Enum.find_value(alts, false, fn alt -> Patterns.match(alt || "") end) ->
        {:ok, :alts, elem(pat, 1), Enum.join(alts, "\n")}

      pat = Patterns.match(embed_title || "") ->
        {:ok, :embed_title, elem(pat, 1), embed_title}

      pat = Patterns.match(embed_description || "") ->
        {:ok, :embed_desc, elem(pat, 1), embed_description}

      true ->
        false
    end
    |> tap(&telem_match(&1, timer))
  end

  defp put_label(post_data, component, pattern, config) do
    %{"uri" => at_uri, "cid" => cid} = post_data

    reason = "#{component} #{pattern}"

    Label.put_label(
      at_uri,
      cid,
      config.label,
      reason,
      config.labeler_did,
      config.session_manager
    )
  end

  defp telem_label(component, pattern) do
    :telemetry.execute([:bsky_labeler, :label], %{}, %{
      pattern: pattern,
      component: component
    })
  end

  defp telem_match(_, start) do
    duration = System.monotonic_time() - start
    :telemetry.execute([:bsky_labeler, :matching], %{duration: duration}, %{})
  end
end
