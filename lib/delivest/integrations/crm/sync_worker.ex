defmodule Delivest.Integrations.Crm.SyncWorker do
  use Oban.Worker,
    queue: :crm,
    max_attempts: 7,
    unique: [period: 300, fields: [:args]]

  require Logger

  alias Delivest.Integrations.{Crm, Health}
  alias Delivest.Integrations.Crm.SyncState
  alias Delivest.Oms.Orders

  @intervals [1, 1, 2, 3, 5, 8, 13]

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}),
    do: Enum.at(@intervals, attempt - 1, List.last(@intervals)) * 10

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"order_id" => order_id}, attempt: attempt} = job) do
    case Orders.get_order(order_id) do
      nil -> {:cancel, :order_not_found}
      order -> order |> Crm.deliver() |> handle(order, attempt, job.max_attempts)
    end
  end

  defp handle({:ok, delivery}, order, attempt, _max_attempts) do
    Logger.info("crm order #{order.number} delivered as #{delivery.external_id}")
    SyncState.sent(order, delivery, attempt)
    Health.recovered(order.crm.provider, order.branch_id)
    :ok
  end

  defp handle({:pending, ref}, order, attempt, _max_attempts) do
    Logger.info("crm order #{order.number} awaits confirmation #{ref}")
    SyncState.confirming(order, ref, attempt)
    Crm.schedule_confirm_check(order)
    :ok
  end

  defp handle({:error, reason} = error, order, attempt, max_attempts) do
    message = inspect(reason)

    Logger.error(
      "crm order #{order.number} attempt #{attempt}/#{max_attempts} failed: #{message}"
    )

    case Crm.classify_error(order, reason) do
      :permanent ->
        SyncState.failed(order, message, attempt)
        {:cancel, reason}

      :auth ->
        SyncState.failed(order, message, attempt)
        Health.auth_failed(order.crm.provider, order.branch_id, reason)
        {:cancel, reason}

      {:snooze, seconds} ->
        SyncState.retrying(order, message, attempt)
        {:snooze, seconds}

      :retry when attempt >= max_attempts ->
        SyncState.failed(order, message, attempt)
        error

      :retry ->
        SyncState.retrying(order, message, attempt)
        error
    end
  end
end
