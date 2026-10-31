defmodule Delivest.Integrations.Crm.OrderSubscriber do
  @behaviour Delivest.Events.Subscriber

  alias Delivest.Integrations.Crm
  alias Delivest.Oms.Order
  alias Delivest.Repo

  @fields %{
    "items" => :update_items,
    "comment" => :update_comment,
    "address" => :update_address,
    "cook_by" => :update_time,
    "payment_method" => :update_payments
  }

  @impl true
  def key, do: :crm

  @impl true
  def events, do: ["order.created", "order.cancelled", "order.updated"]

  @impl true
  def handle(%{actor: %{"kind" => "crm"}, type: type}) when type != "order.created", do: :ok

  def handle(event) do
    case Repo.get(Order, event.aggregate_id) do
      %Order{deleted_at: nil, crm: %{}} = order -> handle(event.type, order, event.payload)
      _order -> :ok
    end
  end

  defp handle("order.created", %Order{crm: %{status: "pending"}} = order, _payload),
    do: Crm.enqueue_sync(order)

  defp handle("order.cancelled", %Order{crm: %{status: "sent"}} = order, _payload) do
    if Crm.can?(order, :cancel),
      do: Crm.enqueue_command(order, "cancel", %{"reason" => order.cancel_reason}),
      else: :ok
  end

  defp handle("order.updated", %Order{crm: %{status: "sent"}} = order, payload) do
    case allowed(order, Map.get(payload, "changes", %{})) do
      changes when changes == %{} -> :ok
      changes -> Crm.enqueue_command(order, "update", %{"changes" => changes})
    end
  end

  defp handle(_type, _order, _payload), do: :ok

  defp allowed(order, changes) do
    Map.filter(changes, fn {field, _change} ->
      case Map.fetch(@fields, field) do
        {:ok, capability} -> Crm.can?(order, capability)
        :error -> false
      end
    end)
  end
end
