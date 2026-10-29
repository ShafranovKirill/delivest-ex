defmodule Delivest.Couriers.OrderSubscriber do
  @behaviour Delivest.Events.Subscriber

  alias Delivest.Couriers
  alias Delivest.Oms.Order
  alias Delivest.Repo

  @impl true
  def key, do: :couriers

  @impl true
  def events, do: ["order.status_changed"]

  @impl true
  def handle(event) do
    case Repo.get(Order, event.aggregate_id) do
      %Order{deleted_at: nil} = order -> Couriers.order_moved(order)
      _order -> :ok
    end
  end
end
