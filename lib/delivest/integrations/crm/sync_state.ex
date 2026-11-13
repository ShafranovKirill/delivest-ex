defmodule Delivest.Integrations.Crm.SyncState do
  use Gettext, backend: DelivestWeb.Gettext

  import Ecto.Query, only: [from: 2]
  require Logger

  alias Delivest.Audit
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Availability
  alias Delivest.Repo
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

  def claim_sending(%Order{} = initial, attempt, generation) do
    case Repo.transaction(fn ->
           Repo.one(
             from(i in BranchInfo, where: i.branch_id == ^initial.branch_id, lock: "FOR SHARE")
           )

           order = Repo.one(from(o in Order, where: o.id == ^initial.id, lock: "FOR UPDATE"))

           case order do
             %{crm: %{status: "pending"}} ->
               if Availability.crm_allowed?(
                    order.branch_id,
                    order.crm.provider,
                    :orders,
                    generation
                  ) do
                 case Orders.update_order_crm(order, %{status: "sending", attempts: attempt}) do
                   {:ok, _} -> :claimed
                   {:error, reason} -> Repo.rollback(reason)
                 end
               else
                 failed(
                   order,
                   "Function disabled or settings changed",
                   attempt,
                   "This order was not sent; check the route and send it explicitly."
                 )

                 :disabled
               end

             %{crm: %{status: status}} ->
               Repo.rollback({:status, status})

             _ ->
               Repo.rollback(:order_not_found)
           end
         end) do
      {:ok, :claimed} -> {:ok, Orders.get_order(initial.id)}
      {:ok, :disabled} -> {:error, :disabled}
      {:error, reason} -> {:error, reason}
    end
  end

  def fail_if_pending(%Order{} = initial, attempt) do
    Repo.transaction(fn ->
      Repo.one(from(i in BranchInfo, where: i.branch_id == ^initial.branch_id, lock: "FOR SHARE"))
      current = Repo.one(from(o in Order, where: o.id == ^initial.id, lock: "FOR UPDATE"))

      if current && current.crm.status == "pending" do
        failed(
          current,
          "Function disabled or settings changed",
          attempt,
          "This order was not sent; check the route and send it explicitly."
        )

        :failed
      else
        :already_started
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

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

  def failed(order, error, attempt, alert \\ nil) do
    Audit.record(:system, "order.crm_failed", order, metadata: %{error: error})
    attrs = %{status: "failed", attempts: attempt, last_error: error}
    attrs = if alert, do: Map.put(attrs, :alert, alert), else: attrs
    Orders.update_order_crm(order, attrs)
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
