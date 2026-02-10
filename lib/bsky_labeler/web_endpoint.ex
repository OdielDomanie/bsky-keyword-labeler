defmodule BskyLabeler.WebEndpoint.Router do
  @moduledoc """
  Mounts `BskyLabeler.PrometheusExporter` on `/metrics` and,
  if `:admin_dashboard_password` is set, `live_dashboard` on `/admin`.
  """
  use Phoenix.Router, helpers: false
  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :put_secure_browser_headers
  end

  pipeline :admin_auth do
    plug :admin_basic_auth
  end

  scope "/admin" do
    pipe_through [:browser, :admin_basic_auth]

    live_dashboard "/dashboard"
  end

  # Prometheus export
  forward "/metrics", BskyLabeler.PrometheusExporter

  defp admin_basic_auth(conn, _opts) do
    username = "admin"
    password = Application.get_env(:bsky_labeler, :admin_dashboard_password)

    if password do
      Plug.BasicAuth.basic_auth(conn, username: username, password: password)
    else
      send_resp(conn, 404, "Not found") |> halt()
    end
  end
end

defmodule BskyLabeler.WebEndpoint do
  @moduledoc """
  Serves the router `BskyLabeler.WebEndpoint.Router`
  """
  use Phoenix.Endpoint, otp_app: :bsky_labeler

  socket("/live", Phoenix.LiveView.Socket,
    websocket: true,
    longpoll: true
  )

  plug Plug.Head

  plug BskyLabeler.WebEndpoint.Router
end
