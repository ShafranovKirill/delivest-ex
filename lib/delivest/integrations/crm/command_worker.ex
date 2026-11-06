defmodule Delivest.Integrations.Crm.CommandWorker do
  use Oban.Worker, queue: :crm, max_attempts: 5

  import Ecto.Query
  require Logger

  alias Delivest.Audit
  alias Delivest.Integrations.Crm
  alias Delivest.Integrations.Crm.CommandDelivery
  alias Delivest.Oms.{Order, Orders}
  alias Delivest.Repo

  @calling_lease_seconds 600

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: attempt * 30

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(2)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"order_id" => order_id} = args, id: id} = job)
      when is_integer(id) do
    logical_id = logical_id(job)

    case claim(job, logical_id) do
      {:ok, :call} ->
        case Orders.get_order(order_id) do
          %Order{crm: %{status: "sent"}} = order ->
            order |> run(args) |> handle(order, args, job)

          _ ->
            finish(logical_id, id, "done", nil)
            {:cancel, :not_sent}
        end

      {:ok, :done} ->
        :ok

      {:error, :waiting} ->
        {:snooze, 30}

      {:error, :unknown} ->
        {:cancel, :unknown_outcome}

      {:error, :order_not_found} ->
        {:cancel, :order_not_found}

      {:error, :duplicate_command} ->
        {:cancel, :duplicate_command}

      {:error, :command_not_found} ->
        {:cancel, :command_not_found}

      {:error, :superseded} ->
        {:cancel, :superseded}

      {:ok, :unknown} ->
        {:cancel, :unknown_outcome}
    end
  end

  defp logical_id(%Oban.Job{id: id, args: args}) do
    case args["command_delivery_id"] do
      logical when is_integer(logical) -> logical
      _ -> id
    end
  end

  defp claim(%Oban.Job{id: execution_id, args: %{"order_id" => order_id} = args}, id) do
    Repo.transaction(fn ->
      lock(order_id)

      if is_nil(Repo.get(Order, order_id)), do: Repo.rollback(:order_not_found)

      ensure_legacy(order_id, id)
      reconcile_prior(order_id, id)

      {:ok, _} =
        Repo.insert(
          %CommandDelivery{
            job_id: id,
            order_id: order_id,
            branch_id: args["branch_id"] || Repo.get!(Order, order_id).branch_id,
            event_id: args["event_id"],
            args: Map.delete(args, "command_delivery_id"),
            execution_job_id: execution_id
          },
          on_conflict: :nothing,
          conflict_target: :job_id
        )

      delivery = Repo.get(CommandDelivery, id)

      if is_nil(delivery) and is_binary(args["event_id"]) and
           Repo.get_by(CommandDelivery, event_id: args["event_id"]),
         do: Repo.rollback(:duplicate_command)

      if is_nil(delivery), do: Repo.rollback(:command_not_found)

      delivery =
        if is_nil(delivery.execution_job_id) do
          delivery
          |> Ecto.Changeset.change(
            execution_job_id: execution_id,
            args: delivery.args || Map.delete(args, "command_delivery_id")
          )
          |> Repo.update!()
        else
          delivery
        end

      cond do
        delivery.execution_job_id not in [nil, execution_id] ->
          Repo.rollback(:superseded)

        delivery.phase == "done" ->
          :done

        delivery.phase in ["unknown", "failed"] ->
          Repo.rollback(:unknown)

        delivery.phase == "calling" and
            DateTime.diff(DateTime.utc_now(), delivery.updated_at, :second) <
              @calling_lease_seconds ->
          Repo.rollback(:waiting)

        delivery.phase == "calling" ->
          set_phase(delivery, "unknown", "Worker stopped during CRM request")
          :unknown

        earlier?(order_id, id) ->
          Repo.rollback(:waiting)

        true ->
          set_phase(delivery, "calling", nil)
          :call
      end
    end)
  end

  defp lock(order_id) do
    Ecto.Adapters.SQL.query!(
      Repo,
      "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
      ["crm_command:#{order_id}"]
    )
  end

  defp ensure_legacy(order_id, id) do
    now = DateTime.utc_now()

    rows =
      Repo.all(
        from(j in Oban.Job,
          where: j.id <= ^id and j.worker == ^Oban.Worker.to_string(__MODULE__),
          where: fragment("?->>'order_id' = ?", j.args, ^order_id),
          select: {j.id, j.args, j.state}
        )
      )

    entries =
      Enum.map(rows, fn {job_id, job_args, state} ->
        %{
          job_id: job_id,
          order_id: order_id,
          branch_id: job_args["branch_id"] || Repo.get!(Order, order_id).branch_id,
          event_id: job_args["event_id"],
          args: job_args,
          execution_job_id: job_id,
          phase:
            case state do
              "completed" -> "done"
              value when value in ["discarded", "cancelled"] -> "unknown"
              _ -> "pending"
            end,
          inserted_at: now,
          updated_at: now
        }
      end)

    if entries != [],
      do: Repo.insert_all(CommandDelivery, entries, on_conflict: :nothing)
  end

  defp earlier?(order_id, id) do
    Repo.exists?(
      from(d in CommandDelivery,
        where: d.order_id == ^order_id and d.job_id < ^id and d.phase != "done"
      )
    )
  end

  defp reconcile_prior(order_id, id) do
    Repo.all(
      from(d in CommandDelivery,
        where: d.order_id == ^order_id and d.job_id < ^id and d.phase == "pending"
      )
    )
    |> Enum.each(fn delivery ->
      case Repo.get(Oban.Job, delivery.execution_job_id || delivery.job_id) do
        nil ->
          set_phase(delivery, "unknown", "Command job was pruned before completion")

        %Oban.Job{state: state} when state in ["discarded", "cancelled"] ->
          set_phase(delivery, "unknown", "Command job stopped before completion")

        _ ->
          :ok
      end
    end)
  end

  defp set_phase(delivery, phase, reason) do
    delivery
    |> Ecto.Changeset.change(phase: phase, last_error: reason)
    |> Repo.update!()
  end

  defp finish(id, execution_id, phase, reason) do
    {count, _} =
      CommandDelivery
      |> where([d], d.job_id == ^id and d.execution_job_id == ^execution_id)
      |> where([d], d.phase == "calling")
      |> Repo.update_all(set: [phase: phase, last_error: reason, updated_at: DateTime.utc_now()])

    case count do
      1 -> :ok
      _ -> {:error, :claim_lost}
    end
  end

  defp run(order, %{"action" => "cancel"} = args),
    do: Crm.cancel(order, args["reason"] && String.to_existing_atom(args["reason"]))

  defp run(order, %{"action" => "update", "changes" => changes}), do: Crm.update(order, changes)

  defp handle(:ok, order, %{"action" => action}, job),
    do: done(order, action, logical_id(job), job.id)

  defp handle({:pending, _ref}, order, %{"action" => action}, job),
    do: done(order, action, logical_id(job), job.id)

  defp handle({:error, reason} = error, order, %{"action" => action}, job) do
    Logger.error("crm order #{order.number} #{action} failed: #{inspect(reason)}")

    case Crm.classify_error(order, reason) do
      :retry when job.attempt < job.max_attempts ->
        finish(logical_id(job), job.id, "pending", inspect(reason))
        error

      {:snooze, seconds} ->
        finish(logical_id(job), job.id, "pending", inspect(reason))
        {:snooze, seconds}

      _ ->
        failed(order, action, reason, logical_id(job), job.id)
    end
  end

  defp done(order, action, id, execution_id) do
    case Repo.transaction(fn ->
           :ok = finish(id, execution_id, "done", nil)
           Audit.record(:system, "order.crm_#{action}", order)
         end) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp failed(order, action, reason, id, execution_id) do
    finish(id, execution_id, "unknown", inspect(reason))

    Audit.record(:system, "order.crm_#{action}_failed", order,
      metadata: %{error: inspect(reason)}
    )

    {:cancel, reason}
  end
end
