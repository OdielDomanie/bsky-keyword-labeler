defmodule BskyLabeler.Repo do
  use Ecto.Repo,
    otp_app: :bsky_labeler,
    adapter: Ecto.Adapters.Postgres
end
