defmodule Delivest.Integrations.Crm.ConfirmWorker do
  use Oban.Worker, queue: :crm, max_attempts: 1

  import Ecto.Query, only: [from: 2]
  require Logger

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.{Availability, Crm}
  alias Delivest.Integrations.Crm.SyncState
  alias Delivest.Oms.{Order, Orders}
  alias Delivest.Repo

  @max_attempts 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"order_id" => order_id}}) do
    case Orders.get_order(order_id) do
      %Order{crm: %{status: "confirming"}} = order -> unconfirmed(order)
      _ -> :ok
    end
  end

  defp unconfirmed(%Order{crm: crm} = order) do
    Logger.warning("crm order #{order.number} not confirmed (#{crm.ref})")

    cond do
      not Availability.crm_allowed?(order.branch_id, crm.provider, :orders) ->
        SyncState.unknown(order, "Sending disabled while confirmation was pending", crm.attempts)
        :ok

      Crm.idempotent?(crm.provider) and crm.attempts < @max_attempts ->
        retry_under_lock(order)

      true ->
        SyncState.failed(order, "not confirmed, check the order in CRM", crm.attempts)
        :ok
    end
  end

  defp retry_under_lock(order) do
    case Repo.transaction(fn ->
           Repo.one(
             from(i in BranchInfo, where: i.branch_id == ^order.branch_id, lock: "FOR SHARE")
           )

           current = Repo.one(from(o in Order, where: o.id == ^order.id, lock: "FOR UPDATE"))

           cond do
             is_nil(current) or current.crm.status != "confirming" ->
               :obsolete

             not Availability.crm_allowed?(current.branch_id, current.crm.provider, :orders) ->
               SyncState.unknown(
                 current,
                 "Sending disabled while confirmation was pending",
                 current.crm.attempts
               )

               :disabled

             true ->
               with {:ok, pending} <-
                      SyncState.retrying(current, "not confirmed", current.crm.attempts),
                    {:ok, %Oban.Job{}} <- Crm.enqueue_sync(pending) do
                 :queued
               else
                 _ -> Repo.rollback(:disabled)
               end
           end
         end) do
      {:ok, _} -> :ok
      {:error, :disabled} -> mark_unknown(order.id)
      {:error, reason} -> {:error, reason}
    end
  end

  defp mark_unknown(order_id) do
    Repo.transaction(fn ->
      current = Repo.one(from(o in Order, where: o.id == ^order_id, lock: "FOR UPDATE"))

      if current && current.crm.status == "confirming" do
        SyncState.unknown(
          current,
          "Sending disabled while confirmation was pending",
          current.crm.attempts
        )
      end
    end)

    :ok
  end
end
