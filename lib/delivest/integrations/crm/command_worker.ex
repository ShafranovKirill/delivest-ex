defmodule Delivest.Integrations.Crm.CommandWorker do
  use Oban.Worker, queue: :crm, max_attempts: 5

  require Logger

  alias Delivest.Audit
  alias Delivest.Integrations.Crm
  alias Delivest.Integrations.Crm.Commands
  alias Delivest.Oms.{Order, Orders}

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: attempt * 30

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    case Commands.claim(job) do
      {:claimed, command, token} ->
        case Orders.get_order(command.order_id) do
          %Order{crm: %{status: "sent", provider: provider}} = order ->
            if to_string(provider) == command.provider do
              order
              |> run(command.action, command.args)
              |> handle(order, command, token, job)
            else
              :ok = Commands.finish(command, token, "failed", "provider changed")
              {:cancel, :provider_changed}
            end

          _ ->
            :ok = Commands.finish(command, token, "failed", "order not sent")
            {:cancel, :not_sent}
        end

      :done ->
        :ok

      :busy ->
        {:snooze, 5}

      :waiting ->
        {:snooze, 15}

      {:error, :busy} ->
        {:snooze, 5}

      {:blocked, _status} ->
        {:cancel, :unknown_outcome}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run(order, "cancel", args),
    do: Crm.cancel(order, args["reason"] && String.to_existing_atom(args["reason"]))

  defp run(order, "update", %{"changes" => changes}), do: Crm.update(order, changes)

  defp handle(:ok, order, command, token, _job), do: done(order, command, token)
  defp handle({:pending, _ref}, order, command, token, _job), do: done(order, command, token)

  defp handle({:error, reason} = error, order, command, token, job) do
    Logger.error("crm order #{order.number} #{command.action} failed: #{inspect(reason)}")

    case Crm.classify_error(order, reason) do
      :unknown_outcome ->
        :ok = Commands.finish(command, token, "unknown", inspect(reason))
        Audit.record(:system, "order.crm_#{command.action}_unknown", order)
        {:cancel, :unknown_outcome}

      :retry when job.attempt < job.max_attempts ->
        :ok = Commands.finish(command, token, "pending", inspect(reason))
        error

      {:snooze, seconds} ->
        :ok = Commands.finish(command, token, "pending", inspect(reason))
        {:snooze, seconds}

      _ ->
        :ok = Commands.finish(command, token, "failed", inspect(reason))

        Audit.record(:system, "order.crm_#{command.action}_failed", order,
          metadata: %{error: inspect(reason)}
        )

        {:cancel, reason}
    end
  end

  defp done(order, command, token) do
    :ok = Commands.finish(command, token, "succeeded")
    Audit.record(:system, "order.crm_#{command.action}", order)
    :ok
  end
end
