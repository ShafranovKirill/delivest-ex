defmodule Delivest.Oms.Kitchen.OrderSubscriber do
  @behaviour Delivest.Events.Subscriber

  alias Delivest.Oms.{Kitchen, Order}
  alias Delivest.Repo

  @impl true
  def key, do: :kitchen

  @impl true
  def events, do: ["order.created", "order.status_changed", "order.updated"]

  @impl true
  def handle(%{type: "order.updated", payload: payload} = event) do
    if Map.has_key?(Map.get(payload, "changes", %{}), "cook_by"),
      do: plan(event),
      else: :ok
  end

  def handle(event), do: plan(event)

  defp plan(event) do
    case Repo.get(Order, event.aggregate_id) do
      %Order{deleted_at: nil, status: :accepted} = order ->
        Kitchen.order_accepted(order)
        :ok

      %Order{} = order ->
        Kitchen.cancel_send(order.id)

      _order ->
        :ok
    end
  end
end
