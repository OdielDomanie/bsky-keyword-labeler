defmodule BskyLabeler.FetchContentStage.Supervisor do
  @moduledoc """
  Supervisor of a set number of `BskyLabeler.FetchContentStage.Worker`s.

  Childspec options:
  * `:subscribe_to_procs` — (required) A list of processes to subscribe.
  * `count` — (required) The number of workers as a positive integer.
      Note that by default `Req` HTTP pool limit is 50 per host tuple.
  * Supervisor options

  A worker stage acts as consumer-producer. It consumes `{post, cid}` events
  emiited by `BskyLabeler.BskyProducer` and emits "post data" per post,
  where "post data" is as returned by the app.bsky.feed.getPosts XRPC call.
  """
  use Supervisor

  def start_link(opts) do
    {stage_opts, sv_opts} = Keyword.split(opts, [:subscribe_to_procs, :count])
    Supervisor.start_link(__MODULE__, stage_opts, sv_opts)
  end

  @doc """
  Gets a value between 0 and 1 representing how congested the worker stages are.

  A value of 1 does not necessarily indicate complete saturation.

  Returns nil after a per worker timeout.
  """
  def congestion(sv, timeout) do
    # As cast because handle_event can block for long, so call may timeout
    # But should be rare unless retyring
    workers = workers(sv)
    Enum.each(workers, fn w -> GenStage.cast(w, {:get_congestion, self()}) end)

    values =
      for _ <- 1..length(workers)//1 do
        receive do
          {:get_congestion_reply, value} -> value
        after
          timeout -> throw(:timeout)
        end
      end

    Enum.sum(values) / length(values)
  catch
    :timeout -> nil
  end

  @doc """
  Returns the list of Worker pids of the BskyLabeler.FetchContentStage.Supervisor supervisor.
  """
  def workers(sv) do
    Supervisor.which_children(sv)
    |> Enum.flat_map(fn
      {id, pid, _worker_or_sv, _modules} ->
        if id
           |> to_string
           |> String.starts_with?("Elixir.BskyLabeler.Pipeline.FetchContentStage.Worker_") do
          [pid]
        else
          []
        end
    end)
  end

  @impl Supervisor
  def init(opts) do
    subscribe_to_procs = opts[:subscribe_to_procs]
    count = Keyword.fetch!(opts, :count)

    # Dynamically generate ids and child specifications.
    # GenStages are restart-permanent by default.
    children =
      for i <- 1..count//1 do
        id = :"Elixir.BskyLabeler.Pipeline.FetchContentStage.Worker_#{i}"

        {BskyLabeler.FetchContentStage.Worker, subscribe_to_procs: subscribe_to_procs}
        |> Supervisor.child_spec(id: id)
      end

    Supervisor.init(children, strategy: :one_for_one)
  end
end

defmodule BskyLabeler.FetchContentStage.Worker do
  @moduledoc false
  alias BskyLabeler.{Base32Sortable, Post}
  require Logger

  use GenStage

  @buffer_timeout 5_000

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts)
  end

  @impl GenStage
  def init(opts) do
    # Max demand 25 because that's the max posts through a single XRPC HTTP API call
    # app.bsky.feed.getPosts
    subscribe_to =
      for proc <- opts[:subscribe_to_procs] do
        {proc, min_demand: 25, max_demand: 50}
      end

    state = %{
      consumer_buffer: :queue.new(),
      consumer_buffer_count: 0,
      buffer_timer: nil,
      congestion: 0
    }

    {:producer_consumer, state, subscribe_to: subscribe_to}
  end

  @impl GenStage
  def handle_cast({:get_congestion, caller}, state) do
    send(caller, {:get_congestion_reply, state.congestion})
    {:noreply, [], state}
  end

  @impl GenStage
  def handle_events(events, _from, state) do
    state = cancel_timer(state)

    new_event_count = length(events)

    if new_event_count + state.consumer_buffer_count < 25 do
      state = update_in(state.consumer_buffer, &:queue.join(&1, :queue.from_list(events)))
      state = update_in(state.consumer_buffer_count, &(&1 + new_event_count))

      state = %{
        state
        | buffer_timer: Process.send_after(self(), :buffer_timeout, @buffer_timeout)
      }

      {:noreply, [], state}
    else
      {new_events_to_handle, to_buffer} = Enum.split(events, 25 - state.consumer_buffer_count)
      events_to_handle = :queue.to_list(state.consumer_buffer) ++ new_events_to_handle

      state = %{
        state
        | consumer_buffer: :queue.from_list(to_buffer),
          consumer_buffer_count: max(0, new_event_count - (25 - state.consumer_buffer_count))
      }

      {produced_events, state} = do_handle_events(events_to_handle, state)

      state = %{
        state
        | buffer_timer: Process.send_after(self(), :buffer_timeout, @buffer_timeout)
      }

      {:noreply, produced_events, state}
    end
  end

  @impl GenStage
  def handle_info(:buffer_timeout, state) do
    state = cancel_timer(state)

    cond do
      state.consumer_buffer_count == 0 ->
        {:noreply, [], state}

      state.consumer_buffer_count > 0 ->
        {events_to_handle, rem} =
          :queue.split(min(25, state.consumer_buffer_count), state.consumer_buffer)

        state = %{
          state
          | consumer_buffer: rem,
            consumer_buffer_count: max(0, state.consumer_buffer_count - 25),
            buffer_timer: Process.send_after(self(), :buffer_timeout, @buffer_timeout)
        }

        events_to_handle = :queue.to_list(events_to_handle)
        {produced_events, state} = do_handle_events(events_to_handle, state)
        {:noreply, produced_events, state}
    end
  end

  def do_handle_events(events, state) do
    {posts, _post_cids} = Enum.unzip(events)

    state = %{state | congestion: length(posts) / 25}

    case fetch_contents(posts) do
      {:ok, post_datas} -> {post_datas, state}
      :error -> {[], state}
    end
  end

  defp cancel_timer(state) do
    if state.buffer_timer do
      Process.cancel_timer(state.buffer_timer, async: true, info: false)
    end

    %{state | buffer_timer: nil}
  end

  defp fetch_contents(posts) when posts != [] do
    at_uris =
      Enum.map(posts, fn %Post{did: did, rkey: rkey} ->
        # Post structs must be only constructed with valid rkeys
        {:ok, rkey_str} = Base32Sortable.encode(rkey)
        "at://" <> did <> "/app.bsky.feed.post/" <> rkey_str
      end)

    uri_params = Enum.map(at_uris, fn uri -> {"uris", uri} end)

    timer = telem_get_posts_start(posts)

    result =
      Req.get("/xrpc/app.bsky.feed.getPosts",
        base_url: "https://public.api.bsky.app",
        params: uri_params,
        retry_log_level: :debug
      )

    case result do
      {:ok, resp} when resp.status === 200 ->
        %{"posts" => posts} = resp.body

        telem_get_posts_stop(timer, :ok)
        if posts == [], do: Logger.debug("getPosts returned empty")

        {:ok, posts}

      {:ok, %{body: %{"error" => reason, "message" => message}}, status: status} ->
        telem_get_posts_stop(timer, {status, reason, message})
        :error

      {:ok, resp} ->
        telem_get_posts_stop(timer, {:status, resp.status})
        :error

      {:error, exc} ->
        telem_get_posts_stop(timer, {:exc, exc})
        :error
    end
  end

  defp telem_get_posts_start(posts) do
    # Logger.debug("Fetching messages of batch size #{to_string(length(posts))}")
    :telemetry.execute([:bsky_labeler, :get_text_http, :start], %{post_count: length(posts)})
    System.monotonic_time()
  end

  # The duration includes retries!
  defp telem_get_posts_stop(timer, event) do
    duration = System.monotonic_time() - timer
    measurements = %{duration: duration}

    metadata =
      case event do
        :ok ->
          %{}

        {status, reason, msg} ->
          %{reason: "#{status}_#{reason}", message: msg}

        {:status, status} ->
          %{reason: "#{status}"}

        {:exc, exc} ->
          %{reason: exc}
      end

    :telemetry.execute([:bsky_labeler, :get_text_http, :stop], measurements, metadata)
  end
end

### EXAMPLE ### resp.body

%{
  "posts" => [
    %{
      "author" => %{
        "associated" => %{
          "activitySubscription" => %{"allowSubscriptions" => "followers"}
        },
        "avatar" =>
          "https://cdn.bsky.app/img/avatar/plain/did:plc:z3ao6ykf6pihzfcbibccxkwa/bafkreicjewjk7apde2jqrkmus2tjkd4qlkqs6jact4g2f2qsr2q4umceny@jpeg",
        "createdAt" => "2025-02-24T23:34:20.346Z",
        "did" => "did:plc:z3ao6ykf6pihzfcbibccxkwa",
        "displayName" => "butterflygirl24",
        "handle" => "butterflygirl24.bsky.social",
        "labels" => []
      },
      "cid" => "bafyreigvmpinxt3ue7czpxepdt4uda37tg74h52vv2x2vuxrf4m6jrlegy",
      "embed" => %{
        "$type" => "app.bsky.embed.video#view",
        "aspectRatio" => %{"height" => 1280, "width" => 720},
        "cid" => "bafkreicdgbwmeqhzulfl5rsgahozpknogimicymyqlaoe3ym2ctgdwviby",
        "playlist" =>
          "https://video.bsky.app/watch/did%3Aplc%3Az3ao6ykf6pihzfcbibccxkwa/bafkreicdgbwmeqhzulfl5rsgahozpknogimicymyqlaoe3ym2ctgdwviby/playlist.m3u8",
        "thumbnail" =>
          "https://video.bsky.app/watch/did%3Aplc%3Az3ao6ykf6pihzfcbibccxkwa/bafkreicdgbwmeqhzulfl5rsgahozpknogimicymyqlaoe3ym2ctgdwviby/thumbnail.jpg"
      },
      "indexedAt" => "2025-08-30T19:20:43.907Z",
      "labels" => [],
      "likeCount" => 713,
      "quoteCount" => 10,
      "record" => %{
        "$type" => "app.bsky.feed.post",
        "createdAt" => "2025-08-30T19:20:41.578Z",
        "embed" => %{
          "$type" => "app.bsky.embed.video",
          "aspectRatio" => %{"height" => 1280, "width" => 720},
          "video" => %{
            "$type" => "blob",
            "mimeType" => "video/mp4",
            "ref" => %{
              "$link" => "bafkreicdgbwmeqhzulfl5rsgahozpknogimicymyqlaoe3ym2ctgdwviby"
            },
            "size" => 1_354_403
          }
        },
        "facets" => [
          %{
            "features" => [
              %{"$type" => "app.bsky.richtext.facet#tag", "tag" => "california"}
            ],
            "index" => %{"byteEnd" => 107, "byteStart" => 96}
          },
          %{
            "features" => [
              %{
                "$type" => "app.bsky.richtext.facet#tag",
                "tag" => "kamalaharris"
              }
            ],
            "index" => %{"byteEnd" => 121, "byteStart" => 108}
          }
        ],
        "langs" => ["en"],
        "text" =>
          "California Highway Patrol stepped up to protect our President. ✊🏼 Y’All know Kamala WON! #california #kamalaharris"
      },
      "replyCount" => 32,
      "repostCount" => 166,
      "uri" => "at://did:plc:z3ao6ykf6pihzfcbibccxkwa/app.bsky.feed.post/3lxnc6gbslc27"
    }
  ]
}

# "embed" => %{
#         "$type" => "app.bsky.embed.external",
#         "external" => %{
#           "$type" => "app.bsky.embed.external#external",
#           "description" => "",
#           "title" => "Original post on liberal.city",
#           "uri" => ###
#         }

nil
