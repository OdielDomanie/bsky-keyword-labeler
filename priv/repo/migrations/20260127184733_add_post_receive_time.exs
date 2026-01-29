defmodule BskyLabeler.Repo.Migrations.AddPostReceiveTime do
  use Ecto.Migration

  def change do
    alter table("posts") do
      add :receive_time, :utc_datetime, null: true
    end
  end
end
