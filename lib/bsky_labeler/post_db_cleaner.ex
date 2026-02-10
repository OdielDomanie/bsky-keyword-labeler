defmodule BskyLabeler.PostDbCleaner do
  @moduledoc """
  Deletes posts older than `retain_secs` from the database table periodically.
  """
  require Logger
  alias BskyLabeler.{Post, Repo}

  use GenServer

  def start_link(retain_secs) do
    GenServer.start_link(__MODULE__, retain_secs)
  end

  @impl true
  def init(retain_secs) do
    {:ok, round(retain_secs), 0}
  end

  @impl true
  def handle_info(:timeout, retain_secs) do
    until = DateTime.utc_now() |> DateTime.add(-retain_secs)

    import Ecto.Query

    q = from p in Post, where: is_nil(p.receive_time) or p.receive_time <= ^until

    # This can take long esp. if not indexed. Typically like 30s, set to 20 min anyways
    {count, nil} = Repo.delete_all(q, timeout: 1_200_000)

    Logger.info("Deleted #{count} rows for cleanup.")

    {:noreply, retain_secs, (retain_secs * 1_000) |> div(2)}
  end
end
