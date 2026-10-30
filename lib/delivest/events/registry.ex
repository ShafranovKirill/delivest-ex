defmodule Delivest.Events.Registry do
  @modules [
    Delivest.Couriers.OrderSubscriber,
    Delivest.Oms.Kitchen.OrderSubscriber,
    Delivest.Push.OrderSubscriber,
    Delivest.Integrations.Crm.OrderSubscriber,
    Delivest.Fiscal.OrderSubscriber,
    Delivest.Payments.OrderSubscriber
  ]

  def modules, do: Application.get_env(:delivest, :event_subscribers, @modules)

  def listening(type), do: Enum.filter(modules(), &(type in &1.events()))

  def fetch(key) do
    case Enum.find(modules(), &(to_string(&1.key()) == to_string(key))) do
      nil -> {:error, :unknown_subscriber}
      module -> {:ok, module}
    end
  end
end
