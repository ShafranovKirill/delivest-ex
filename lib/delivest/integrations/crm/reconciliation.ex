defmodule Delivest.Integrations.Crm.Reconciliation do
  import Ecto.Query

  alias Delivest.{Audit, Identity, Repo}
  alias Delivest.Integrations.Crm
  alias Delivest.Oms.Order

  def resolve(staff, branch_id, order_id, action, number \\ nil)

  def resolve(staff, branch_id, order_id, action, number)
      when action in ["exists", "resend"] do
    with :ok <- Identity.authorize(staff, "orders.update", branch_id),
         :ok <- validate_number(action, number),
         {:ok, uuid} <- Ecto.UUID.cast(order_id) do
      case Repo.transaction(fn -> reconcile(staff, branch_id, uuid, action, number) end) do
        {:ok, result} -> result
        {:error, error} -> error
      end
    else
      {:error, :forbidden} = error -> error
      {:error, :number_required} = error -> error
      _ -> {:error, :order_not_found}
    end
  end

  def resolve(_staff, _branch_id, _order_id, _action, _number),
    do: {:error, :unknown_action}

  defp reconcile(staff, branch_id, order_id, action, number) do
    order =
      Repo.one(
        from(o in Order,
          where: o.id == ^order_id and o.branch_id == ^branch_id and is_nil(o.deleted_at),
          lock: "FOR UPDATE"
        )
      )

    with %Order{crm: %{status: "unknown"}} <- order,
         true <- action != "resend" or order.status not in [:cancelled, :completed],
         {:ok, updated} <- Crm.resolve_alert(staff, branch_id, order_id, action, number),
         {:ok, _audit} <-
           Audit.record(staff, audit_action(action), updated,
             metadata: %{result: audit_result(action), provider: updated.crm.provider}
           ) do
      {:ok, updated}
    else
      %Order{} -> Repo.rollback({:error, :not_reconcilable})
      false -> Repo.rollback({:error, :not_reconcilable})
      nil -> Repo.rollback({:error, :order_not_found})
      error -> Repo.rollback(error)
    end
  end

  defp audit_action("exists"), do: "order.crm_reconciled_exists"
  defp audit_action("resend"), do: "order.crm_resend_requested"

  defp audit_result("exists"), do: "confirmed_existing"
  defp audit_result("resend"), do: "queued"

  defp validate_number("exists", number) when is_binary(number) do
    if String.trim(number) == "", do: {:error, :number_required}, else: :ok
  end

  defp validate_number("exists", _number), do: {:error, :number_required}
  defp validate_number("resend", _number), do: :ok
end
