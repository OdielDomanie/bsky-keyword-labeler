defmodule BskyLabeler.Post do
  use Ecto.Schema

  @primary_key false
  schema "posts" do
    # rkey is a https://atproto.com/specs/tid
    field :rkey, :integer, primary_key: true
    field :did, :string, primary_key: true
    field :likes, :integer, default: 0
  end
end
