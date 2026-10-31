defmodule Delivest.Integrations.Crm.CommandWorker do
  use Oban.Worker, queue: :crm, max_attempts: 5

  require Logger

  alias Delivest.Audit
  alias Delivest.Integrations.Crm
  alias Delivest.Oms.{Order, Orders}

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: attempt * 30

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"order_id" => order_id} = args} = job) do
    case Orders.get_order(order_id) do
      %Order{crm: %{status: "sent"}} = order -> order |> run(args) |> handle(order, args, job)
      _ -> {:cancel, :not_sent}
    end
  end

  defp run(order, %{"action" => "cancel"} = args),
    do: Crm.cancel(order, args["reason"] && String.to_existing_atom(args["reason"]))

  defp run(order, %{"action" => "update", "changes" => changes}), do: Crm.update(order, changes)

  defp handle(:ok, order, %{"action" => action}, _job), do: done(order, action)
  defp handle({:pending, _ref}, order, %{"action" => action}, _job), do: done(order, action)

  defp handle({:error, reason} = error, order, %{"action" => action}, job) do
    Logger.error("crm order #{order.number} #{action} failed: #{inspect(reason)}")

    case Crm.classify_error(order, reason) do
      :retry when job.attempt < job.max_attempts -> error
      {:snooze, seconds} -> {:snooze, seconds}
      _ -> failed(order, action, reason)
    end
  end

  defp done(order, action) do
    Audit.record(:system, "order.crm_#{action}", order)
    :ok
  end

  defp failed(order, action, reason) do
    Audit.record(:system, "order.crm_#{action}_failed", order,
      metadata: %{error: inspect(reason)}
    )

    {:cancel, reason}
  end
end
