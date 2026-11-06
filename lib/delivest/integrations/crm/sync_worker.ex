defmodule Delivest.Integrations.Crm.SyncWorker do
  use Oban.Worker,
    queue: :crm,
    max_attempts: 7,
    unique: [period: 300, fields: [:args]]

  require Logger

  alias Delivest.Integrations.{Crm, Health}
  alias Delivest.Integrations.Crm.SyncState
  alias Delivest.Oms.Orders
  alias Delivest.Oms.Order
  alias Delivest.Repo
  import Ecto.Query

  @intervals [1, 1, 2, 3, 5, 8, 13]
  @sending_lease_seconds 600

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}),
    do: Enum.at(@intervals, attempt - 1, List.last(@intervals)) * 10

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(2)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"order_id" => order_id}, attempt: attempt} = job) do
    case claim(order_id, attempt) do
      {:ok, %Order{} = order} ->
        result = order |> Crm.deliver() |> handle(order, attempt, job.max_attempts)
        report(order, result, attempt)
        result

      {:ok, :uncertain} ->
        {:cancel, :unknown_outcome}

      {:error, :sending} ->
        {:snooze, 30}

      {:error, reason} ->
        {:cancel, reason}
    end
  end

  defp claim(order_id, attempt) do
    Repo.transaction(fn ->
      case Repo.one(from(o in Order, where: o.id == ^order_id, lock: "FOR UPDATE")) do
        %Order{crm: %{status: status}} = order when status in ["pending", "failed"] ->
          case Orders.update_order_crm(order, %{
                 status: "sending",
                 sending_started_at: DateTime.utc_now(:second)
               }) do
            {:ok, claimed} -> claimed
            {:error, reason} -> Repo.rollback(reason)
          end

        %Order{crm: %{status: "sending", provider: provider, sending_started_at: started}} = order ->
          age =
            if started,
              do: DateTime.diff(DateTime.utc_now(), started, :second),
              else: @sending_lease_seconds

          cond do
            age < @sending_lease_seconds ->
              Repo.rollback(:sending)

            Crm.idempotent?(provider) ->
              case Orders.update_order_crm(order, %{sending_started_at: DateTime.utc_now(:second)}) do
                {:ok, claimed} -> claimed
                {:error, reason} -> Repo.rollback(reason)
              end

            true ->
              case SyncState.unknown(
                     order,
                     "CRM request may have completed before worker stopped",
                     attempt
                   ) do
                {:ok, _updated} -> :uncertain
                {:error, reason} -> Repo.rollback(reason)
              end
          end

        nil ->
          Repo.rollback(:order_not_found)

        _other ->
          Repo.rollback(:not_pending)
      end
    end)
  end

  defp handle({:ok, delivery}, order, attempt, _max_attempts) do
    Logger.info("crm order #{order.number} delivered as #{delivery.external_id}")

    case SyncState.sent(order, delivery, attempt) do
      {:ok, _updated} ->
        Health.recovered(order.crm.provider, order.branch_id)
        :ok

      error ->
        error
    end
  end

  defp handle({:pending, ref}, order, attempt, _max_attempts) do
    Logger.info("crm order #{order.number} awaits confirmation #{ref}")

    case Repo.transaction(fn ->
           with {:ok, _updated} <- SyncState.confirming(order, ref, attempt),
                {:ok, _job} <- Crm.schedule_confirm_check(order) do
             :ok
           else
             {:error, reason} -> Repo.rollback(reason)
           end
         end) do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
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

      :unknown_outcome ->
        SyncState.unknown(order, message, attempt)
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

  defp report(order, result, attempt) do
    :telemetry.execute(
      [:delivest, :crm, :sync],
      %{count: 1},
      %{
        provider: (order.crm && order.crm.provider) || "unknown",
        result: outcome(result),
        attempt: attempt
      }
    )
  end

  defp outcome(:ok), do: :delivered
  defp outcome({:snooze, _seconds}), do: :snoozed
  defp outcome({:cancel, _reason}), do: :cancelled
  defp outcome({:error, _reason}), do: :retrying
end
