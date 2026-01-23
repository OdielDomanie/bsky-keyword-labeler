defmodule BskyLabeler.Repo.Migrations.CreatePosts do
  use Ecto.Migration

  def change do
    create table("posts", primary_key: false) do
      # bigint is 8-byte signed, rkey first bit is always zero
      add :rkey, :bigint, primary_key: true
      add :did, :text, primary_key: true
      add :likes, :integer, null: false
    end
  end
end
