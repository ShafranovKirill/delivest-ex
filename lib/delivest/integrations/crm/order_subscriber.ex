defmodule Delivest.Integrations.Crm.OrderSubscriber do
  @behaviour Delivest.Events.Subscriber
  import Ecto.Query

  alias Delivest.Events.Event
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
      %Order{deleted_at: nil, crm: %{}} = order ->
        handle(event.type, order, event.payload, event.id)

      _order ->
        :ok
    end
  end

  defp handle("order.created", %Order{crm: %{status: "pending"}} = order, _payload, _event_id),
    do: Crm.enqueue_sync(order)

  defp handle("order.cancelled", %Order{crm: %{provider: provider}} = order, _payload, event_id)
       when is_binary(provider) do
    if initial_started?(order) and Crm.can?(order, :cancel),
      do: Crm.enqueue_command(order, "cancel", %{"reason" => order.cancel_reason}, event_id),
      else: :ok
  end

  defp handle("order.updated", %Order{crm: %{provider: provider}} = order, payload, event_id)
       when is_binary(provider) do
    changes =
      if initial_started?(order), do: allowed(order, Map.get(payload, "changes", %{})), else: %{}

    case changes do
      changes when changes == %{} -> :ok
      changes -> Crm.enqueue_command(order, "update", %{"changes" => changes}, event_id)
    end
  end

  defp handle(_type, _order, _payload, _event_id), do: :ok

  defp initial_started?(%Order{crm: %{status: status}}) when status != "pending", do: true

  defp initial_started?(%Order{crm: crm, id: order_id}) do
    (crm.attempts || 0) > 0 or
      Repo.exists?(
        from(e in Event,
          where:
            e.aggregate_type == "order" and e.aggregate_id == ^order_id and
              e.type == "order.created"
        )
      )
  end

  defp allowed(order, changes) do
    Map.filter(changes, fn {field, _change} ->
      case Map.fetch(@fields, field) do
        {:ok, capability} -> Crm.can?(order, capability)
        :error -> false
      end
    end)
  end
end
