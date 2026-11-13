defmodule Delivest.Integrations.Crm.SyncWorker do
  use Oban.Worker,
    queue: :crm,
    max_attempts: 7,
    unique: [period: 300, fields: [:args]]

  require Logger

  alias Delivest.Integrations.{Availability, Crm, Health}
  alias Delivest.Integrations.Crm.{FrontpadStopRefresh, SyncState}
  alias Delivest.Oms.Orders

  @intervals [1, 1, 2, 3, 5, 8, 13]

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}),
    do: Enum.at(@intervals, attempt - 1, List.last(@intervals)) * 10

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"order_id" => order_id}, attempt: attempt} = job) do
    case Orders.get_order(order_id) do
      nil ->
        {:cancel, :order_not_found}

      %{crm: %{status: "sending"}} = order ->
        if attempt > 1 do
          SyncState.unknown(order, "Worker stopped after starting CRM delivery", attempt)
          {:cancel, :unknown_outcome}
        else
          {:cancel, :already_sending}
        end

      %{crm: %{status: status}} when status != "pending" ->
        {:cancel, :order_not_pending}

      order ->
        result =
          if fresh?(order, job.args) do
            case SyncState.claim_sending(order, attempt, job.args["generation"]) do
              {:ok, sending} ->
                case Crm.deliver(sending, job.args["generation"]) do
                  {:error, :disabled} ->
                    SyncState.failed(
                      sending,
                      "Function disabled or settings changed",
                      attempt,
                      "This order was not sent; check the route and send it explicitly."
                    )

                    {:cancel, :disabled}

                  delivery ->
                    handle(delivery, sending, attempt, job.max_attempts)
                end

              {:error, {:status, "sending"}} ->
                {:cancel, :already_sending}

              {:error, :disabled} ->
                {:cancel, :disabled}

              {:error, {:status, _status}} ->
                {:cancel, :order_not_pending}

              {:error, reason} ->
                {:error, reason}
            end
          else
            case SyncState.fail_if_pending(order, attempt) do
              :failed -> {:cancel, :disabled}
              :already_started -> {:cancel, :already_started}
              error -> error
            end
          end

        report(order, result, attempt)
        result
    end
  end

  defp fresh?(order, %{"generation" => generation}) when is_integer(generation),
    do: Availability.crm_allowed?(order.branch_id, order.crm.provider, :orders, generation)

  defp fresh?(_order, _args), do: false

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
    maybe_refresh_frontpad_stops(order, reason)
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

  defp maybe_refresh_frontpad_stops(
         %{crm: %{provider: provider}, branch_id: branch_id},
         {:frontpad, "invalid_product_keys"}
       )
       when provider in [:frontpad, "frontpad"] do
    FrontpadStopRefresh.request_internal(branch_id, :product_rejected)
  rescue
    _error -> Logger.warning("Frontpad stop refresh dispatch failed")
  catch
    kind, _reason when kind in [:exit, :throw] ->
      Logger.warning("Frontpad stop refresh dispatch failed")
  end

  defp maybe_refresh_frontpad_stops(_order, _reason), do: :ok

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
