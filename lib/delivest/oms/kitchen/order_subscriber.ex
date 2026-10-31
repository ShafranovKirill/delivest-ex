defmodule Delivest.Oms.Kitchen.OrderSubscriber do
  @behaviour Delivest.Events.Subscriber

  alias Delivest.Oms.{Kitchen, Order}
  alias Delivest.Repo

  @impl true
  def key, do: :kitchen

  @impl true
  def events, do: ["order.created", "order.status_changed"]

  @impl true
  def handle(event) do
    case Repo.get(Order, event.aggregate_id) do
      %Order{deleted_at: nil} = order -> Kitchen.order_accepted(order)
      _order -> :ok
    end
  end
end
