defmodule Delivest.Integrations.Poller do
  alias Delivest.Integrations.Poller.Worker

  @callback key() :: atom()
  @callback targets() :: [String.t()]
  @callback poll(target :: String.t()) ::
              :done | :more | {:snooze, pos_integer()} | {:ok, term()} | {:error, term()}
  @callback interval() :: pos_integer()

  @modules [
    Delivest.Integrations.YandexDelivery.Poller,
    Delivest.Integrations.Crm.StopPoller,
    Delivest.Integrations.Crm.CatalogPoller,
    Delivest.Integrations.Crm.SilencePoller,
    Delivest.Integrations.Rkeeper.Poller,
    Delivest.Integrations.YandexEda.BusyPoller,
    Delivest.Integrations.AtolOnline.KktPoller,
    Delivest.Integrations.Dadata.Poller,
    Delivest.Integrations.Yookassa.Reconciliation,
    Delivest.Integrations.YandexRating.Poller
  ]

  def modules, do: @modules

  def fetch(key) do
    case Enum.find(@modules, &(to_string(&1.key()) == to_string(key))) do
      nil -> {:error, :unknown_poller}
      module -> {:ok, module}
    end
  end

  def enqueue(module, target, opts \\ []) do
    if module.key() in [:crm_catalog, :crm_stops, :dadata, :yandex_eda_busy, :yandex_rating] and
         target not in module.targets(),
       do: {:ok, :disabled},
       else: args(module, target) |> Worker.new(opts) |> Oban.insert()
  end

  def enqueue_all(module) do
    module.targets()
    |> Enum.map(&Worker.new(args(module, &1)))
    |> Oban.insert_all()

    :ok
  end

  defp args(module, target) do
    base = %{poller: to_string(module.key()), target: target}

    if module.key() in [:crm_catalog, :crm_stops] do
      Map.put(base, :generation, Delivest.Integrations.Crm.get_branch_settings(target).generation)
    else
      base
    end
  end
end
