defmodule BskyLabeler.Post do
  @moduledoc """
  A dry Bluesky post.
  """
  use Ecto.Schema

  @primary_key false
  schema "posts" do
    # rkey is a https://atproto.com/specs/tid
    field :rkey, :integer, primary_key: true
    field :did, :string, primary_key: true
    field :likes, :integer, default: 0
    # nullable for migration
    field :receive_time, :utc_datetime
  end
end
