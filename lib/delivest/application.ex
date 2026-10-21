defmodule Delivest.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  import Cachex.Spec, only: [hook: 1]

  @impl true
  def start(_type, _args) do
    children = [
      DelivestWeb.Telemetry,
      Delivest.Repo,
      log_buffer(),
      {DNSCluster, query: Application.get_env(:delivest, :dns_cluster_query) || :ignore},
      {Oban, Application.fetch_env!(:delivest, Oban)},
      {Phoenix.PubSub, name: Delivest.PubSub},
      # Start a worker by calling: Delivest.Worker.start_link(arg)
      # {Delivest.Worker, arg},
      # Start to serve requests, typically the last entry
      Supervisor.child_spec({Cachex, name: :staff_cache}, id: :staff_cache),
      Supervisor.child_spec({Cachex, name: :branch_cache}, id: :branch_cache),
      Supervisor.child_spec({Cachex, name: :menu_cache}, id: :menu_cache),
      Supervisor.child_spec({Cachex, name: :stock_cache}, id: :stock_cache),
      Supervisor.child_spec(
        {Cachex,
         name: :cart_cache, hooks: [hook(module: Cachex.Limit.Scheduled, args: {10_000, [], []})]},
        id: :cart_cache
      ),
      Supervisor.child_spec({Cachex, name: :promo_cache}, id: :promo_cache),
      Supervisor.child_spec({Cachex, name: :franchise_cache}, id: :franchise_cache),
      Supervisor.child_spec({Cachex, name: :rate_limit_cache}, id: :rate_limit_cache),
      DelivestWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Delivest.Supervisor]

    Delivest.Logs.ObanErrors.attach()
    Supervisor.start_link(Enum.reject(children, &is_nil/1), opts)
  end

  defp log_buffer do
    if Delivest.Logs.enabled?(), do: {Delivest.Logs.Buffer, level: Delivest.Logs.level()}
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DelivestWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
