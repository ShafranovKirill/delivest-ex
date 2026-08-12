defmodule Delivest.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      DelivestWeb.Telemetry,
      Delivest.Repo,
      {DNSCluster, query: Application.get_env(:delivest, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Delivest.PubSub},
      # Start a worker by calling: Delivest.Worker.start_link(arg)
      # {Delivest.Worker, arg},
      # Start to serve requests, typically the last entry
      {Cachex, name: :staff_cache},
      DelivestWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Delivest.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DelivestWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
