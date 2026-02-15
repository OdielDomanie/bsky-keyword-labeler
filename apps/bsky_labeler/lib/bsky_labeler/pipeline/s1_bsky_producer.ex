defmodule BskyLabeler.BskyProducer do
  @moduledoc """
  `GenStage` **producer**.

  Childspec options:
  * `:config_manager` — (required) `BskyLabeler.ConfigManager` instance
  * `name`

  Config manager keys:
  * `:min_likes` — (required) positive integer.

  Requires `BskyLabeler.Repo`.

  Connects to the Bluesky jetstream websocket.

  Inserts newly created posts. Increments their like counts with every like received.
  Once the number of likes are above `min_likes`, the post is **deleted** from the repo,
  and the event is emitted.

  Needs continous demand to keep the websocket alive. Built on `BskyLabeler.Utils.WebsocketProducer`.

  Emits `{%Post{}, post_cid}`.
  """
  alias BskyLabeler.{Base32Sortable, ConfigManager, Post, Repo}
  alias BskyLabeler.Utils.WebsocketProducer
  import DateTime, only: [utc_now: 1]
  require Logger

  @jetstream_instances ["jetstream1.us-east.bsky.network", "jetstream2.us-east.bsky.network"]

  def child_spec(opts) do
    config_manager = Keyword.fetch!(opts, :config_manager)
    name = opts[:name]

    uri = fn ->
      host = Enum.random(@jetstream_instances)

      %URI{
        scheme: "wss",
        host: host,
        port: 443,
        path: "/subscribe",
        query: "wantedCollections=app.bsky.feed.post&wantedCollections=app.bsky.feed.like"
      }
    end

    flat_mapper = %{acc: %{cm: config_manager}, fun: &__MODULE__.flat_mapper/2}

    event_cb = &__MODULE__.telemetry/1

    WebsocketProducer.child_spec(
      uri: uri,
      flat_mapper: flat_mapper,
      event_cb: event_cb,
      name: name
    )
  end

  @doc false
  def flat_mapper(frame, config) do
    {decode_and_filter(frame, config), config}
  end

  defp decode_and_filter({:text, string}, config) do
    # Decode
    at_event = JSON.decode!(string)

    telemetry_cursor(at_event["time_us"])

    at_event(at_event, config)
  end

  ### New Post, or Post Update
  defp at_event(
         %{
           "kind" => "commit",
           "commit" => %{
             "operation" => op,
             "collection" => "app.bsky.feed.post",
             "rkey" => rkey
           },
           "did" => did
         },
         _config
       )
       when op == "create" or op == "update" do
    case op do
      "create" -> telemetry_post_received()
      "update" -> telemetry_post_updated()
    end

    # Sometimes the rkey is not valid
    case Base32Sortable.decode(rkey) do
      {:ok, rkey_int} ->
        post = %Post{did: did, rkey: rkey_int, likes: 0, receive_time: utc_now(:second)}
        # May be deleted and re-posted at same key, or may be an update
        Repo.insert!(post, on_conflict: :replace_all, conflict_target: [:rkey, :did])

      {:error, _} ->
        telemetry_post_bad_rkey()
    end

    # Not above the like limit yet
    []
  end

  ### Post Delete
  defp at_event(
         %{
           "kind" => "commit",
           "commit" => %{
             "operation" => "delete",
             "collection" => "app.bsky.feed.post",
             "rkey" => rkey
           },
           "did" => did
         },
         _
       ) do
    telemetry_post_deleted()

    case Base32Sortable.decode(rkey) do
      {:ok, rkey_int} ->
        # allow_stale because posts older than the program may be deleted.
        Repo.delete!(%Post{did: did, rkey: rkey_int}, allow_stale: true)

      {:error, _} ->
        nil
    end

    []
  end

  ### New Like
  defp at_event(
         %{
           "kind" => "commit",
           "commit" => %{
             "collection" => "app.bsky.feed.like",
             "operation" => "create",
             "record" => %{
               "subject" => %{
                 # "uri" => "at://did:plc:yd5kblmvvmaeit2jhhdq2wry/app.bsky.feed.post/3lxjqbs7cac2l"
                 "uri" => "at://" <> subject_at_uri,
                 "cid" => subject_cid
               }
             }
           }
         },
         config
       ) do
    [subject_did, post_type, subject_rkey] = String.split(subject_at_uri, "/")

    rkey_result = Base32Sortable.decode(subject_rkey)
    # Feed generators can also receive likes.
    # Sometimes rkeys are illegal tids (eg. first bit 1)
    if post_type == "app.bsky.feed.post" and match?({:ok, _}, rkey_result) do
      telemetry_post_like()

      {:ok, subject_rkey_int} = rkey_result

      import Ecto.Query

      # Increment likes of the post
      {_, posts} =
        from(p in Post,
          where: p.did == ^subject_did,
          where: p.rkey == ^subject_rkey_int,
          select: p
        )
        |> Repo.update_all(inc: [likes: 1])

      min_likes = min_likes(config)

      # The post may not be in db
      case posts do
        [%Post{likes: likes} = post] when likes >= min_likes ->
          telemetry_post_pass_treshold()

          Repo.delete!(post)

          [{post, subject_cid}]

        _ ->
          []
      end
    else
      []
    end
  end

  ### Deleted Like
  defp at_event(
         %{
           "kind" => "commit",
           "commit" => %{
             "operation" => "delete",
             "collection" => "app.bsky.feed.like"
           }
         },
         _
       ) do
    # Deletes don't have record data, so simply ignore for simplicity.
    []
  end

  ### Account and Identity are always received, ignore
  defp at_event(%{"kind" => kind}, _)
       when kind == "account"
       when kind == "identity" do
    []
  end

  defp at_event(event, state) do
    Logger.warning("Unknown event: #{inspect(event)}")
    state
  end

  defp min_likes(%{cm: config_manager}) do
    ConfigManager.get(config_manager, :min_likes) || raise "min_likes not set"
  end

  ### TELEMETRY

  defp telemetry_cursor(time_us) do
    if time_us do
      :telemetry.execute([:bsky_labeler, :cursor], %{time_us: time_us}, %{})
    end
  end

  defp telemetry_post_received, do: :telemetry.execute([:bsky_labeler, :post_received], %{})
  defp telemetry_post_deleted, do: :telemetry.execute([:bsky_labeler, :post_deleted], %{})
  defp telemetry_post_updated, do: :telemetry.execute([:bsky_labeler, :post_updated], %{})
  defp telemetry_post_bad_rkey, do: :telemetry.execute([:bsky_labeler, :post_bad_rkey], %{})
  defp telemetry_post_like, do: :telemetry.execute([:bsky_labeler, :post_like], %{})

  defp telemetry_post_pass_treshold,
    do: :telemetry.execute([:bsky_labeler, :post_pass_treshold], %{})

  @doc false
  def telemetry(websocket_event) do
    case websocket_event do
      {:connecting, uri} ->
        Logger.info("Connecting to #{uri}")

      {:connect_error, reason, reconnect_after} ->
        Logger.error(
          "Error when trying to connect: #{Exception.message(reason)}. Retrying in #{reconnect_after}"
        )

      :open ->
        Logger.info("Open")

      {:closing, reason} ->
        Logger.info("Closing: " <> inspect(reason))

      {:closed, reason, nil} ->
        Logger.info("Remote closed with #{inspect(reason)}")

      {:closed, reason, reconnect_after} ->
        :telemetry.execute([:bsky_labeler, :ws_closed], %{}, %{reason: reason})

        Logger.error("Remote closed with #{inspect(reason)}. Reconnecting in #{reconnect_after}")
    end
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
