defmodule Delivest.Integrations.Crm.SyncState do
  alias Delivest.Audit
  alias Delivest.Oms.Orders

  def sent(order, external_id, attempt) do
    Audit.record(:system, "order.sent_to_crm", order, metadata: %{external_id: external_id})

    Orders.update_order_crm(order, %{
      status: "sent",
      external_id: external_id,
      attempts: attempt,
      last_error: nil,
      sent_at: DateTime.utc_now(:second)
    })
  end

  def retrying(order, error, attempt),
    do: Orders.update_order_crm(order, %{status: "pending", attempts: attempt, last_error: error})

  def failed(order, error, attempt) do
    Audit.record(:system, "order.crm_failed", order, metadata: %{error: error})
    Orders.update_order_crm(order, %{status: "failed", attempts: attempt, last_error: error})
  end
end
