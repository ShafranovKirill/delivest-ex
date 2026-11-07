defmodule Delivest.Events.Recovery do
  @moduledoc "Staff-authorized recovery for stopped event deliveries."
  import Ecto.Query

  alias Delivest.Audit.Event, as: AuditEvent
  alias Delivest.Events.{DeliverWorker, Delivery, Event}
  alias Delivest.Identity
  alias Delivest.Identity.Staff
  alias Delivest.Repo

  @worker "Delivest.Events.DeliverWorker"
  @active_states ~w(available scheduled executing retryable suspended)

  def list(limit \\ 100) when is_integer(limit) and limit in 1..100 do
    Repo.all(
      from d in Delivery,
        join: e in Event,
        on: e.id == d.event_id,
        where: d.status == "pending",
        order_by: [asc: d.inserted_at],
        limit: ^limit,
        select: %{
          event_id: e.id,
          aggregate_type: e.aggregate_type,
          aggregate_id: e.aggregate_id,
          sequence: e.sequence,
          subscriber: d.subscriber,
          pending_since: d.inserted_at
        }
    )
    |> Enum.map(fn item -> Map.put(item, :jobs, jobs(item.event_id, item.subscriber)) end)
  end

  def retry(event_id, subscriber, actor_id, reason),
    do: change(:retry, event_id, subscriber, actor_id, reason)

  def resolve(event_id, subscriber, actor_id, reason),
    do: change(:resolve, event_id, subscriber, actor_id, reason)

  defp change(action, event_id, subscriber, actor_id, reason) do
    with {:ok, event_id} <- Ecto.UUID.cast(event_id),
         {:ok, actor_id} <- Ecto.UUID.cast(actor_id),
         true <- is_binary(subscriber) and subscriber != "",
         true <- is_binary(reason) and String.trim(reason) != "" do
      Repo.transaction(fn ->
        actor =
          Repo.get(Staff, actor_id)
          |> case do
            %Staff{deleted_at: nil} = staff -> Repo.preload(staff, :role)
            _ -> Repo.rollback(:forbidden)
          end

        unless Identity.admin_staff?(actor), do: Repo.rollback(:forbidden)

        event = Repo.get(Event, event_id) || Repo.rollback(:event_not_found)

        lock_key = "#{event.aggregate_type}:#{event.aggregate_id}:#{subscriber}"

        %{rows: [[locked?]]} =
          Repo.query!("SELECT pg_try_advisory_xact_lock(hashtextextended($1, 0))", [lock_key])

        unless locked?, do: Repo.rollback(:busy_delivery)

        delivery =
          Repo.one(
            from d in Delivery,
              where: d.event_id == ^event_id and d.subscriber == ^subscriber,
              lock: "FOR UPDATE"
          ) || Repo.rollback(:delivery_not_found)

        unless delivery.status == "pending", do: Repo.rollback(:already_closed)

        prior_jobs = jobs(event_id, subscriber)
        if job_exists?(event_id, subscriber, @active_states), do: Repo.rollback(:active_job)
        if job_exists?(event_id, subscriber, ["completed"]), do: Repo.rollback(:already_completed)

        case action do
          :retry ->
            case Oban.insert(
                   DeliverWorker.new(%{event_id: event_id, subscriber: subscriber},
                     queue: Delivest.Events.queue(subscriber)
                   )
                 ) do
              {:ok, %Oban.Job{conflict?: false}} -> :ok
              {:ok, %Oban.Job{conflict?: true}} -> Repo.rollback(:job_conflict)
              {:error, error} -> Repo.rollback(error)
            end

          :resolve ->
            now = DateTime.utc_now()

            Repo.update_all(
              from(d in Delivery, where: d.event_id == ^event_id and d.subscriber == ^subscriber),
              set: [status: "resolved", resolved_at: now, updated_at: now]
            )
        end

        Repo.insert!(%AuditEvent{
          action: "events.#{action}",
          actor_type: :staff,
          actor_id: actor.id,
          actor_name: actor.name || actor.login,
          subject_type: "domain_event",
          subject_id: event.id,
          subject_label: "#{event.type}:#{subscriber}",
          branch_id: event.branch_id,
          metadata: %{
            subscriber: subscriber,
            reason: String.trim(reason),
            previous_status: delivery.status,
            previous_jobs: prior_jobs
          }
        })

        :ok
      end)
    else
      _ -> {:error, :invalid_arguments}
    end
  end

  defp jobs(event_id, subscriber) do
    Repo.all(
      from j in Oban.Job,
        where: j.worker == ^@worker,
        where: fragment("?->>'event_id'", j.args) == ^event_id,
        where: fragment("?->>'subscriber'", j.args) == ^subscriber,
        order_by: [desc: j.id],
        limit: 5,
        select: %{id: j.id, state: j.state, attempt: j.attempt, max_attempts: j.max_attempts}
    )
  end

  defp job_exists?(event_id, subscriber, states) do
    Repo.exists?(
      from j in Oban.Job,
        where: j.worker == ^@worker and j.state in ^states,
        where: fragment("?->>'event_id'", j.args) == ^event_id,
        where: fragment("?->>'subscriber'", j.args) == ^subscriber
    )
  end
end
