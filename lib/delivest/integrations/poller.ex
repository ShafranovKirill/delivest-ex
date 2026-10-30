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
    Delivest.Integrations.Rkeeper.Poller
  ]

  def modules, do: @modules

  def fetch(key) do
    case Enum.find(@modules, &(to_string(&1.key()) == to_string(key))) do
      nil -> {:error, :unknown_poller}
      module -> {:ok, module}
    end
  end

  def enqueue(module, target, opts \\ []),
    do: %{poller: to_string(module.key()), target: target} |> Worker.new(opts) |> Oban.insert()

  def enqueue_all(module) do
    module.targets()
    |> Enum.map(&Worker.new(%{poller: to_string(module.key()), target: &1}))
    |> Oban.insert_all()

    :ok
  end
end
