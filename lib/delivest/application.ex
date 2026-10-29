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
      cache(:staff_cache),
      cache(:branch_cache),
      cache(:menu_cache),
      cache(:stock_cache),
      cache(:cart_cache, limit: 10_000),
      cache(:promo_cache),
      cache(:franchise_cache),
      cache(:rate_limit_cache, limit: 100_000),
      cache(:geo_cache, limit: 50_000),
      cache(:crm_cache),
      cache(:stop_cache),
      DelivestWeb.KitchenPresence,
      DelivestWeb.CourierPresence,
      DelivestWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Delivest.Supervisor]

    Delivest.Logs.ObanErrors.attach()
    Supervisor.start_link(Enum.reject(children, &is_nil/1), opts)
  end

  defp cache(name, opts \\ []) do
    hooks =
      case Keyword.fetch(opts, :limit) do
        {:ok, limit} -> [hook(module: Cachex.Limit.Scheduled, args: {limit, [], []})]
        :error -> []
      end

    Supervisor.child_spec({Cachex, name: name, hooks: hooks}, id: name)
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
