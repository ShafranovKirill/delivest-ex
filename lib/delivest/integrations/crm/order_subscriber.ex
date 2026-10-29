defmodule Delivest.Integrations.Crm.OrderSubscriber do
  @behaviour Delivest.Events.Subscriber

  alias Delivest.Integrations.Crm
  alias Delivest.Oms.Order
  alias Delivest.Repo

  @impl true
  def key, do: :crm

  @impl true
  def events, do: ["order.created"]

  @impl true
  def handle(event) do
    case Repo.get(Order, event.aggregate_id) do
      %Order{deleted_at: nil, crm: %{status: "pending"}} = order -> Crm.enqueue_sync(order)
      _order -> :ok
    end
  end
end
