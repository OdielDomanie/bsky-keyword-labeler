defmodule Ocr.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Ocr.QueueManager, name: Ocr.QueueManager, max_current: System.schedulers_online()}
    ]

    opts = [strategy: :one_for_one, name: Ocr.Supervisor, max_seconds: 10]
    Supervisor.start_link(children, opts)
  end
end
