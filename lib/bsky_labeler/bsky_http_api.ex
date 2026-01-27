defmodule BskyLabeler.BskyHttpApi do
  alias BskyLabeler.{Post, Base32Sortable}

  @spec get_text(struct()) :: %{
          text: String.t(),
          alts: [String.t()],
          embed_title: String.t() | nil,
          embed_desc: String.t() | nil
        }
  def get_text(%Post{did: did, rkey: rkey}) do
    {:ok, rkey} = Base32Sortable.encode(rkey)
    at_uri = "at://" <> did <> "/app.bsky.feed.post/" <> rkey

    # dbg(at_uri)

    # TELEMETRY
    resp_fun = fn ->
      resp =
        Req.get!("/xrpc/app.bsky.feed.getPosts",
          base_url: "https://public.api.bsky.app",
          params: [uris: at_uri]
        )

      if resp.status >= 400 do
        throw({:http_status, resp.status})
      end

      {resp, %{}}
    end

    event_prefix = [:bsky_labeler, :get_text_http]
    # Emits stop suffix event with duration in native units, and monotonic_time
    # or emits with exception suffix the same + metadata: reason
    resp = :telemetry.span(event_prefix, %{}, resp_fun)

    # dbg(did <> "/post/" <> Base32Sortable.encode!(rkey))

    %{
      "posts" => [
        %{
          "record" => %{
            "text" => text
          }
        } = post
      ]
    } = resp.body

    images = post["record"]["embed"]["images"] || []

    alts =
      for %{"alt" => alt} <- images, alt != "" do
        alt
      end

    embed_title = post["embed"]["external"]["title"]
    embed_description = post["embed"]["external"]["description"]

    %{text: text, alts: alts, embed_title: embed_title, embed_desc: embed_description}
  end
end

## resp.body

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
