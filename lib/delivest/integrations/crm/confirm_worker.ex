defmodule Delivest.Integrations.Crm.ConfirmWorker do
  use Oban.Worker, queue: :crm, max_attempts: 1

  require Logger

  alias Delivest.Integrations.Crm
  alias Delivest.Integrations.Crm.SyncState
  alias Delivest.Oms.{Order, Orders}

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

    if Crm.idempotent?(crm.provider) and crm.attempts < @max_attempts do
      {:ok, order} = SyncState.retrying(order, "not confirmed", crm.attempts)
      Crm.enqueue_sync(order)
      :ok
    else
      SyncState.failed(order, "not confirmed, check the order in CRM", crm.attempts)
      :ok
    end
  end
end
