defmodule Delivest.Integrations.Crm.SyncState do
  use Gettext, backend: DelivestWeb.Gettext

  require Logger

  alias Delivest.Audit
  alias Delivest.Oms.{Order, OrderFlow, Orders}

  def sent(order, delivery, attempt) do
    warnings = Map.get(delivery, :warnings)

    if warnings,
      do: Logger.warning("crm order #{order.number} accepted with warnings: #{inspect(warnings)}")

    Audit.record(:system, "order.sent_to_crm", order,
      metadata: %{external_id: delivery.external_id, warnings: warnings}
    )

    advance(order, :accepted, %{
      status: "sent",
      external_id: delivery.external_id,
      external_number: Map.get(delivery, :external_number),
      warnings: warnings,
      alert: Map.get(delivery, :alert),
      attempts: attempt,
      last_error: nil,
      sent_at: DateTime.utc_now(:second)
    })
  end

  def confirming(order, ref, attempt),
    do:
      Orders.update_order_crm(order, %{
        status: "confirming",
        ref: ref,
        attempts: attempt,
        last_error: nil
      })

  def remote_status(order, status, code, at) do
    if is_nil(status),
      do: Logger.warning("crm order #{order.number} got unmapped status code #{code}")

    status = forward_only(order, status)

    Audit.record(:system, "order.crm_status_changed", order,
      metadata: %{status: status, code: code}
    )

    advance(order, status, %{
      remote_status: status && to_string(status),
      remote_status_code: code,
      remote_status_at: at
    })
  end

  def retrying(order, error, attempt),
    do: Orders.update_order_crm(order, %{status: "pending", attempts: attempt, last_error: error})

  def unknown(order, error, attempt) do
    Audit.record(:system, "order.crm_unknown", order, metadata: %{error: error})

    Orders.update_order_crm(order, %{
      status: "unknown",
      attempts: attempt,
      last_error: error,
      alert:
        gettext(
          "The answer was lost. Check in the CRM whether order %{number} exists and confirm or resend it",
          number: order.number
        )
    })
  end

  def acknowledge_alert(order), do: Orders.update_order_crm(order, %{alert: nil})

  def failed(order, error, attempt) do
    Audit.record(:system, "order.crm_failed", order, metadata: %{error: error})
    Orders.update_order_crm(order, %{status: "failed", attempts: attempt, last_error: error})
  end

  defp advance(order, status, crm) do
    Orders.advance_order(order, status || order.status, :crm,
      with: &Order.crm_changeset(&1, crm),
      attrs: %{cancel_reason: :other, cancel_note: gettext("Cancelled in CRM")}
    )
  end

  defp forward_only(%{crm: %{remote_status: current}}, nil) when is_binary(current),
    do: String.to_existing_atom(current)

  defp forward_only(_order, nil), do: nil

  defp forward_only(%{crm: %{remote_status: current}} = order, status) when is_binary(current) do
    if OrderFlow.ahead?(String.to_existing_atom(current), status) do
      status
    else
      Logger.warning("crm order #{order.number} tried to move back from #{current} to #{status}")
      String.to_existing_atom(current)
    end
  end

  defp forward_only(_order, status), do: status
end
