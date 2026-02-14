defmodule BskyLabeler.Repo.Migrations.AlterTableUnlogged do
  use Ecto.Migration

  def change do
    execute "ALTER TABLE posts SET UNLOGGED", "ALTER TABLE posts SET LOGGED"
  end
end
