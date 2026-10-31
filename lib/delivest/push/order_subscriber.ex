defmodule Delivest.Push.OrderSubscriber do
  @behaviour Delivest.Events.Subscriber

  alias Delivest.Oms.Order
  alias Delivest.{Push, Repo}

  @impl true
  def key, do: :push

  @impl true
  def events, do: ["order.created", "order.status_changed", "order.cancelled"]

  @impl true
  def handle(event) do
    case Repo.get(Order, event.aggregate_id) do
      %Order{deleted_at: nil} = order -> notify(event, order)
      _order -> :ok
    end
  end

  defp notify(%{type: "order.created"}, %Order{status: :created} = order),
    do: Push.notify_staff(:order_created, order.id)

  defp notify(%{type: "order.status_changed"}, order), do: Push.order_changed(order)

  defp notify(%{type: "order.cancelled", actor: %{"kind" => "channel"}}, order),
    do: Push.notify_staff(:channel_cancelled, order.id)

  defp notify(_event, _order), do: :ok
end
