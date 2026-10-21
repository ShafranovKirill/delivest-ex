defmodule Delivest.Integrations.Crm.SyncState do
  require Logger

  alias Delivest.Audit
  alias Delivest.Oms.Orders

  def sent(order, delivery, attempt) do
    warnings = Map.get(delivery, :warnings)

    if warnings,
      do: Logger.warning("crm order #{order.number} accepted with warnings: #{inspect(warnings)}")

    Audit.record(:system, "order.sent_to_crm", order,
      metadata: %{external_id: delivery.external_id, warnings: warnings}
    )

    Orders.update_order_crm(order, %{
      status: "sent",
      external_id: delivery.external_id,
      external_number: Map.get(delivery, :external_number),
      warnings: warnings,
      attempts: attempt,
      last_error: nil,
      sent_at: DateTime.utc_now(:second)
    })
  end

  def remote_status(order, status, code, at) do
    if is_nil(status),
      do: Logger.warning("crm order #{order.number} got unmapped status code #{code}")

    Audit.record(:system, "order.crm_status_changed", order,
      metadata: %{status: status, code: code}
    )

    Orders.update_order_crm(order, %{
      remote_status: status && to_string(status),
      remote_status_code: code,
      remote_status_at: at
    })
  end

  def retrying(order, error, attempt),
    do: Orders.update_order_crm(order, %{status: "pending", attempts: attempt, last_error: error})

  def failed(order, error, attempt) do
    Audit.record(:system, "order.crm_failed", order, metadata: %{error: error})
    Orders.update_order_crm(order, %{status: "failed", attempts: attempt, last_error: error})
  end
end
