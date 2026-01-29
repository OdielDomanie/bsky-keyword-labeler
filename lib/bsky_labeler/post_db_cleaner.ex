defmodule BskyLabeler.PostDbCleaner do
  require Logger
  alias BskyLabeler.Repo
  alias BskyLabeler.Post

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

    {count, nil} = Repo.delete_all(q)

    Logger.info("Deleted #{count} rows for cleanup.")

    {:noreply, retain_secs, (retain_secs * 1_000) |> div(2)}
  end
end
