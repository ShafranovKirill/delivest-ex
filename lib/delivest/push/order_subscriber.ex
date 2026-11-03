defmodule Delivest.Push.OrderSubscriber do
  @behaviour Delivest.Events.Subscriber

  alias Delivest.Oms.Order
  alias Delivest.{Push, Repo}

  @impl true
  def key, do: :push

  @impl true
  def events, do: ["order.created", "order.status_changed", "order.cancelled", "order.updated"]

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

  # The operator marked a position as unavailable and saved the order. The
  # client learns which position is gone and what the new total is, and keeps
  # the usual right to cancel the order from the app.
  defp notify(%{type: "order.updated", actor: %{"kind" => "staff"}, payload: payload}, order) do
    payload
    |> removed_titles()
    |> then(&Push.notify_items_removed(order, &1))
  end

  defp notify(_event, _order), do: :ok

  defp removed_titles(%{"changes" => %{"items" => %{"from" => from, "to" => to}}}) do
    left = count(from)

    to
    |> count()
    |> Enum.reduce(left, fn {key, quantity}, acc ->
      Map.update(acc, key, 0, &max(&1 - quantity, 0))
    end)
    |> Enum.filter(fn {_title, quantity} -> quantity > 0 end)
    |> Enum.map(fn {title, _quantity} -> title end)
  end

  defp removed_titles(_payload), do: []

  defp count(items) when is_list(items) do
    Enum.reduce(items, %{}, fn item, acc ->
      title = item["title"]
      quantity = item["quantity"] || 0

      if is_binary(title) and quantity > 0,
        do: Map.update(acc, title, quantity, &(&1 + quantity)),
        else: acc
    end)
  end

  defp count(_items), do: %{}
end
