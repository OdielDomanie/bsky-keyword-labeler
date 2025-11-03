defmodule BskyPoliticsLabeler.Websocket do
  alias BskyPoliticsLabeler.{Post, Repo, Label, Base32Sortable}
  alias Wesex.Connection
  require Logger

  use GenServer

  @instances ["jetstream1.us-east.bsky.network", "jetstream2.us-east.bsky.network"]
  @retry_time 15_000

  def start_link(opts) do
    # {wesex_opts, genserver_opts} = Keyword.split(opts, [:url, :headers, :adapter_opts, :init_arg])
    {config, genserver_opts} = Keyword.split(opts, [:labeler_did, :session_manager, :min_likes])
    genserver_opts = Keyword.put_new(genserver_opts, :name, __MODULE__)

    GenServer.start_link(__MODULE__, config, genserver_opts)
  end

  @impl GenServer
  def init(config) do
    labeler_did = config[:labeler_did]
    session_manager = config[:session_manager]
    true = !!labeler_did
    true = !!session_manager

    Process.flag(:trap_exit, true)

    {:ok,
     %{
       conn: nil,
       counter: %{},
       reconnect_timer: nil,
       labeler_did: labeler_did,
       session_manager: session_manager,
       min_likes: config[:min_likes] || 50
     }, {:continue, :connect}}
  end

  @impl GenServer
  def handle_continue(:connect, state) do
    nil = state.conn
    instance = Enum.random(@instances)

    uri = %URI{
      scheme: "wss",
      host: instance,
      port: 443,
      path: "/subscribe",
      query: "wantedCollections=app.bsky.feed.post&wantedCollections=app.bsky.feed.like"
    }

    Logger.info("URI: #{uri}")

    case Connection.connect(uri, [], Wesex.MintAdapter, conn: [protocols: [:http1]]) do
      {:ok, conn} ->
        {:noreply, %{state | conn: conn}}

      {:error, reason} ->
        Logger.error(
          "Error when trying to connect: #{inspect(reason)}. Retrying in #{@retry_time}"
        )

        timer = Process.send_after(self(), :retry, @retry_time)
        {:noreply, %{state | reconnect_timer: timer}}
    end
  end

  @impl GenServer
  def handle_info(:retry, state) do
    state = %{state | reconnect_timer: nil}
    handle_continue(:connect, state)
  end

  def handle_info(info, %{conn: nil} = state) do
    Logger.debug("Message received when conn nil: #{inspect(info, limit: 3)}")
    {:noreply, state}
  end

  def handle_info(info, %{conn: conn} = state) do
    {events, c} = Connection.event(conn, info)
    do_events(%{state | conn: c}, events)
  end

  @impl GenServer
  def terminate(reason, state) do
    if (reason == :shutdown or match?({:shutdown, _}, reason)) and state.conn do
      Logger.info("Shutting down, sending close 1000")
      {events, conn} = Connection.close(state.conn, {1000, nil})
      receive_until_close(events, conn)
    end
  end

  defp receive_until_close([], conn) do
    receive do
      info ->
        case Connection.event(conn, info) do
          false ->
            Logger.warning("Received unhandles message: " <> inspect(info))

          {result_events, conn} ->
            receive_until_close(result_events, conn)
        end
    end
  end

  defp receive_until_close([{:received, {:text, _post}} | rest], conn) do
    # Logger.debug("Received after sent close:\n" <> post)
    receive_until_close(rest, conn)
  end

  defp receive_until_close([{:closing, reason} | rest], conn) do
    Logger.info("Closing: " <> inspect(reason))
    receive_until_close(rest, conn)
  end

  defp receive_until_close([{:closed, reason} | rest], conn) do
    Logger.info("Closed: " <> inspect(reason))
    receive_until_close(rest, conn)
  end

  defp do_events(state, []), do: {:noreply, state}

  defp do_events(state, [{:received, {:text, atevent_json}} | rest]) do
    atevent = Jason.decode!(atevent_json)
    state = receive_atevent(atevent, state)
    do_events(state, rest)
  end

  defp do_events(state, [:open | rest]) do
    Logger.info("Open")
    do_events(state, rest)
  end

  defp do_events(state, [{:closing, reason} | rest]) do
    Logger.info("Closing: " <> inspect(reason))
    do_events(state, rest)
  end

  defp do_events(state, [{:closed, reason} | _rest]) do
    Logger.error("Remote closed with #{inspect(reason)}. Reconnecting in #{@retry_time}")

    timer = Process.send_after(self(), :retry, @retry_time)
    {:noreply, %{state | reconnect_timer: timer, conn: nil}}
  end

  ### New Post
  def receive_atevent(
        %{
          "kind" => "commit",
          "commit" => %{
            "operation" => "create",
            "collection" => "app.bsky.feed.post",
            "rkey" => rkey
          },
          "did" => did
        },
        state
      ) do
    case Base32Sortable.decode(rkey) do
      {:ok, rkey_int} ->
        # Sometimes there is a pkey conflict.
        Repo.insert!(%Post{did: did, rkey: rkey_int, likes: 0}, on_conflict: :nothing)

      {:error, _} ->
        nil
    end

    state
  end

  ### Post Delete
  def receive_atevent(
        %{
          "kind" => "commit",
          "commit" => %{
            "operation" => "delete",
            "collection" => "app.bsky.feed.post",
            "rkey" => rkey
          },
          "did" => did
        },
        state
      ) do
    case Base32Sortable.decode(rkey) do
      {:ok, rkey_int} ->
        # allow_stale because posts older than the program may be deleted.
        Repo.delete(%Post{did: did, rkey: rkey_int}, allow_stale: true)

      {:error, _} ->
        nil
    end

    state
  end

  ### Post Update
  # Bsky doesn't support edits and it doesn't display updates,
  # but some tools like Bridgy do commit updates.
  def receive_atevent(
        %{
          "kind" => "commit",
          "commit" => %{
            "operation" => "update",
            "collection" => "app.bsky.feed.post"
          }
        },
        state
      ) do
    state
  end

  ### New Like
  def receive_atevent(
        %{
          "kind" => "commit",
          "commit" => %{
            "cid" => cid,
            "operation" => "create",
            "collection" => "app.bsky.feed.like",
            "record" => %{
              "subject" => %{
                "uri" => "at://" <> subject_at_uri
                # "uri" => "at://did:plc:yd5kblmvvmaeit2jhhdq2wry/app.bsky.feed.post/3lxjqbs7cac2l"
              }
            }
          }
        },
        state
      ) do
    [subject_did, post_type, subject_rkey] = String.split(subject_at_uri, "/")

    rkey_result = Base32Sortable.decode(subject_rkey)
    # Feed generators can also receive likes.
    # Sometimes rkeys are illegal tids (first bit 1)
    if post_type == "app.bsky.feed.post" and match?({:ok, _}, rkey_result) do
      {:ok, subject_rkey_int} = rkey_result

      import Ecto.Query

      {_, posts} =
        from(p in Post,
          where: p.did == ^subject_did,
          where: p.rkey == ^subject_rkey_int,
          select: p
        )
        |> Repo.update_all(inc: [likes: 1])

      case posts do
        [%Post{likes: likes} = post] when likes >= state.min_likes ->
          res =
            Task.Supervisor.start_child(Label.TaskSV, fn ->
              Label.label(post, cid, state.labeler_did, state.session_manager)
            end)

          if match?({:error, _reason}, res) do
            {:error, reason} = res
            Logger.warning("Could not start task: #{inspect(reason)}")
          end

          Repo.delete!(post)

        _ ->
          nil
      end
    end

    state
  end

  ### Deleted Like
  def receive_atevent(
        %{
          "kind" => "commit",
          "commit" => %{
            "operation" => "delete",
            "collection" => "app.bsky.feed.like"
          }
        },
        state
      ) do
    # Deletes don't have record data, so simply ignore for simplicity.
    state
  end

  def receive_atevent(%{"kind" => kind}, state)
      when kind == "account"
      when kind == "identity" do
    state
  end

  def receive_atevent(event, state) do
    Logger.warning("Unknown event: #{inspect(event)}")
    state
  end
end

# Sample events

%{
  "commit" => %{
    "cid" => "bafyreicnefhcv7k22gicu272s6jgb3oufiz5324jwq5uzkqhbnmkozjvem",
    "collection" => "app.bsky.feed.post",
    "operation" => "create",
    "record" => %{
      "$type" => "app.bsky.feed.post",
      "createdAt" => "2025-06-18T14:51:27.685Z",
      "embed" => %{
        "$type" => "app.bsky.embed.images",
        "images" => [
          %{
            "alt" => "",
            "aspectRatio" => %{"height" => 1080, "width" => 1080},
            "image" => %{
              "$type" => "blob",
              "mimeType" => "image/jpeg",
              "ref" => %{"$link" => "bafkreifdpj2wu56tyhfvs5t56winyqy5ynmnkli3iae2nkercfvznuktwq"},
              "size" => 629_473
            }
          }
        ]
      },
      "facets" => [
        %{
          "features" => [
            %{"$type" => "app.bsky.richtext.facet#tag", "tag" => "nonviolentcommunication"}
          ],
          "index" => %{"byteEnd" => 24, "byteStart" => 0}
        },
        %{
          "features" => [
            %{"$type" => "app.bsky.richtext.facet#tag", "tag" => "LeadWithCompassion"}
          ],
          "index" => %{"byteEnd" => 44, "byteStart" => 25}
        },
        %{
          "features" => [%{"$type" => "app.bsky.richtext.facet#tag", "tag" => "NoJudgmentZone"}],
          "index" => %{"byteEnd" => 60, "byteStart" => 45}
        },
        %{
          "features" => [%{"$type" => "app.bsky.richtext.facet#tag", "tag" => "empathymatters"}],
          "index" => %{"byteEnd" => 76, "byteStart" => 61}
        },
        %{
          "features" => [
            %{"$type" => "app.bsky.richtext.facet#tag", "tag" => "KindnessIsStrength"}
          ],
          "index" => %{"byteEnd" => 96, "byteStart" => 77}
        },
        %{
          "features" => [
            %{"$type" => "app.bsky.richtext.facet#tag", "tag" => "emotionalintelligence"}
          ],
          "index" => %{"byteEnd" => 119, "byteStart" => 97}
        },
        %{
          "features" => [%{"$type" => "app.bsky.richtext.facet#tag", "tag" => "mindfulliving"}],
          "index" => %{"byteEnd" => 134, "byteStart" => 120}
        },
        %{
          "features" => [%{"$type" => "app.bsky.richtext.facet#tag", "tag" => "seethegood"}],
          "index" => %{"byteEnd" => 146, "byteStart" => 135}
        },
        %{
          "features" => [%{"$type" => "app.bsky.richtext.facet#tag", "tag" => "BreakTheCycle"}],
          "index" => %{"byteEnd" => 161, "byteStart" => 147}
        },
        %{
          "features" => [%{"$type" => "app.bsky.richtext.facet#tag", "tag" => "innerpeace"}],
          "index" => %{"byteEnd" => 173, "byteStart" => 162}
        },
        %{
          "features" => [
            %{"$type" => "app.bsky.richtext.facet#tag", "tag" => "judgmentfreeleadership"}
          ],
          "index" => %{"byteEnd" => 197, "byteStart" => 174}
        }
      ],
      "langs" => ["en"],
      "text" =>
        "#nonviolentcommunication #LeadWithCompassion #NoJudgmentZone #empathymatters #KindnessIsStrength #emotionalintelligence #mindfulliving #seethegood #BreakTheCycle #innerpeace #judgmentfreeleadership"
    },
    "rev" => "3lrvb42z3s52m",
    "rkey" => "3lrvb3s3hes24"
  },
  "did" => "did:plc:7rxiipc26y4qx2eiq3rrnwhf",
  "kind" => "commit",
  "time_us" => 1_750_258_298_427_081
}

%{
  "commit" => %{
    "collection" => "app.bsky.feed.post",
    "operation" => "delete",
    "rev" => "3lrvbcdrlan27",
    "rkey" => "3lruzezqoqk2a"
  },
  "did" => "did:plc:rfrqhevj7poexpydwulex52e",
  "kind" => "commit",
  "time_us" => 1_750_258_507_815_755
}

%{
  "account" => %{
    "active" => false,
    "did" => "did:plc:qmpizivuuqeljnc3vnpjcfdz",
    "seq" => 10_441_040_594,
    "status" => "deleted",
    "time" => "2025-06-18T14:57:30.337Z"
  },
  "did" => "did:plc:qmpizivuuqeljnc3vnpjcfdz",
  "kind" => "account",
  "time_us" => 1_750_258_651_505_322
}

%{
  "did" => "did:plc:udx7uhdsnan67uboikweoe7n",
  "identity" => %{
    "did" => "did:plc:udx7uhdsnan67uboikweoe7n",
    "handle" => "93moon9.bsky.social",
    "seq" => 10_441_090_436,
    "time" => "2025-06-18T14:59:05.746Z"
  },
  "kind" => "identity",
  "time_us" => 1_750_258_746_192_759
}

%{
  "commit" => %{
    "cid" => "bafyreiad4r2gblrdet4nns7gvmb6tjtb2kv6mn5a7kj7pxissykfykwxbq",
    "collection" => "app.bsky.feed.post",
    "operation" => "update",
    "record" => %{
      "$type" => "app.bsky.feed.post",
      "bridgyOriginalText" =>
        "<p>we need a national comparison of state and local governments to get some baseline costs and understanding of the best way to provide services. then I&#39;d support much higher taxes on the wealthy by the feds to then transfer down to those governments in order to alleviate the state and local taxes paid by everybody. more transparency and less pain by transferring costs onto those who can most easily afford it. <a href=\"https://liberal.city/tags/uspol\" class=\"mention hashtag\" rel=\"tag\">#<span>uspol</span></a></p>",
      "bridgyOriginalUrl" => "https://liberal.city/@wjmaggos/114704934818203702",
      "createdAt" => "2025-06-18T14:53:24.000Z",
      "embed" => %{
        "$type" => "app.bsky.embed.external",
        "external" => %{
          "$type" => "app.bsky.embed.external#external",
          "description" => "",
          "title" => "Original post on liberal.city",
          "uri" => "https://liberal.city/@wjmaggos/114704934818203702"
        }
      },
      "langs" => ["en"],
      "tags" => ["USpol"],
      "text" =>
        "we need a national comparison of state and local governments to get some baseline costs and understanding of the best way to provide services. then I'd support much higher taxes on the wealthy by the feds to then transfer down to those governments in order to alleviate the state and local taxes […]"
    },
    "rev" => "222222pb2pi22",
    "rkey" => "3lrvba4ksbjc2"
  },
  "did" => "did:plc:tu5mcgb2rtnafl6gfc53ozmg",
  "kind" => "commit",
  "time_us" => 1_750_258_922_694_630
}

## Like

%{
  "did" => "did:plc:uzatm7eruomb5mk7rrqi4sfn",
  "time_us" => 1_756_459_368_050_202,
  "kind" => "commit",
  "commit" => %{
    "rev" => "3lxjqcexl5k2y",
    "operation" => "create",
    "collection" => "app.bsky.feed.like",
    "rkey" => "3lxjqcewyls2y",
    "record" => %{
      "$type" => "app.bsky.feed.like",
      "createdAt" => "2025-08-29T09=>22=>47.006Z",
      "subject" => %{
        "cid" => "bafyreih7xlri7lrpujvlmbtmqyzfuh2jlx2zqtkbfa3md2syl33kvri5n4",
        "uri" => "at://did:plc:yd5kblmvvmaeit2jhhdq2wry/app.bsky.feed.post/3lxjqbs7cac2l"
      }
    },
    "cid" => "bafyreigbrkb45kpnyhawtuewgyhyrsbocd3q652lplwr3ynedwo3yxt4ga"
  }
}

## Like delete
%{
  "did" => "did:plc:7yi4fmwrazwdk37rbhw6amp6",
  "time_us" => 1_756_562_619_603_797,
  "kind" => "commit",
  "commit" => %{
    "rev" => "3lxmqgkqrnn2f",
    "operation" => "delete",
    "collection" => "app.bsky.feed.like",
    "rkey" => "3lxmqgjpxln2l"
  }
}

nil
