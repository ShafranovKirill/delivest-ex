defmodule Delivest.Events.DeliverWorker do
  use Oban.Worker,
    queue: :events,
    max_attempts: 10,
    unique: [period: :infinity, keys: [:event_id, :subscriber]]

  require Logger

  import Ecto.Query

  alias Delivest.Events.{Delivery, Event, Registry}
  alias Delivest.Repo

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: min(trunc(:math.pow(2, attempt)) * 5, 1800)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event_id" => id, "subscriber" => key}} = job) do
    with {:ok, module} <- Registry.fetch(key),
         %Event{} = event <- Repo.get(Event, id) || {:error, :event_not_found} do
      event
      |> deliver(module, key)
      |> result(event, key, job)
    else
      {:error, reason} -> {:cancel, reason}
    end
  end

  defp deliver(event, module, key) do
    case Repo.transaction(fn ->
           lock_aggregate(event, key)

           {:ok, _delivery} =
             Repo.insert(%Delivery{event_id: event.id, subscriber: key},
               on_conflict: :nothing,
               conflict_target: [:event_id, :subscriber]
             )

           delivery = Repo.get_by!(Delivery, event_id: event.id, subscriber: key)

           cond do
             delivery.status == "delivered" ->
               :already_delivered

             delivery.status == "blocked" ->
               {:cancel, :delivery_blocked}

             earlier?(event, key) ->
               {:snooze, 5}

             true ->
               case module.handle(event) do
                 result when result == :ok or (is_tuple(result) and elem(result, 0) == :ok) ->
                   delivery
                   |> Ecto.Changeset.change(status: "delivered", last_error: nil)
                   |> Repo.update!()

                   :delivered

                 error ->
                   Repo.rollback(error)
               end
           end
         end) do
      {:ok, :delivered} -> :ok
      {:ok, :already_delivered} -> :already_delivered
      {:ok, outcome} -> outcome
      {:error, error} -> error
    end
  end

  defp lock_aggregate(event, key) do
    lock_key = "#{event.aggregate_type}:#{event.aggregate_id}:#{key}"

    Ecto.Adapters.SQL.query!(Repo, "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
      lock_key
    ])
  end

  defp earlier?(event, key) do
    previous =
      Repo.all(
        from(d in Delivery,
          join: e in Event,
          on: e.id == d.event_id,
          where: d.subscriber == ^key and d.status != "delivered",
          where:
            e.aggregate_type == ^event.aggregate_type and e.aggregate_id == ^event.aggregate_id,
          where: e.sequence < ^event.sequence,
          select: d
        )
      )

    Enum.each(previous, &reconcile_terminal/1)

    Repo.exists?(
      from(d in Delivery,
        join: e in Event,
        on: e.id == d.event_id,
        where: d.subscriber == ^key and d.status != "delivered",
        where:
          e.aggregate_type == ^event.aggregate_type and e.aggregate_id == ^event.aggregate_id,
        where: e.sequence < ^event.sequence
      )
    )
  end

  defp reconcile_terminal(%Delivery{status: "pending"} = delivery) do
    states =
      Repo.all(
        from(j in Oban.Job,
          where: j.worker == ^Oban.Worker.to_string(__MODULE__),
          where: fragment("?->>'event_id' = ?", j.args, ^delivery.event_id),
          where: fragment("?->>'subscriber' = ?", j.args, ^delivery.subscriber),
          select: j.state
        )
      )

    cond do
      Enum.any?(states, &(&1 in ["available", "scheduled", "retryable", "executing"])) ->
        :ok

      "completed" in states ->
        set_status(delivery, "delivered", nil)

      true ->
        set_status(delivery, "blocked", "Delivery job stopped or was pruned")
    end
  end

  defp reconcile_terminal(_delivery), do: :ok

  defp set_status(delivery, status, reason) do
    Delivery
    |> where([d], d.event_id == ^delivery.event_id and d.subscriber == ^delivery.subscriber)
    |> where([d], d.status == "pending")
    |> Repo.update_all(set: [status: status, last_error: reason])
  end

  defp result(:ok, event, key, _job) do
    report_delivery(event, key)
    :ok
  end

  defp result(:already_delivered, _event, _key, _job), do: :ok
  defp result({:snooze, _seconds} = snooze, _event, _key, _job), do: snooze

  defp result({:ok, _value}, event, key, job), do: result(:ok, event, key, job)

  defp result({:cancel, reason} = cancel, event, key, _job) do
    block(event, key, reason)
    Logger.error("event #{event.type} #{event.id} cancelled for #{key}: #{inspect(reason)}")
    cancel
  end

  defp result({:error, reason} = error, event, key, %Oban.Job{attempt: attempt} = job)
       when attempt >= job.max_attempts do
    block(event, key, reason)
    Logger.error("event #{event.type} #{event.id} not delivered to #{key}: #{inspect(reason)}")
    error
  end

  defp result({:error, _reason} = error, _event, _key, _job), do: error

  defp block(event, key, reason) do
    Delivery
    |> where([d], d.event_id == ^event.id and d.subscriber == ^key and d.status != "delivered")
    |> Repo.update_all(set: [status: "blocked", last_error: inspect(reason)])
  end

  defp report_delivery(event, key) do
    lag = DateTime.diff(DateTime.utc_now(), event.inserted_at, :millisecond)

    :telemetry.execute(
      [:delivest, :outbox, :delivered],
      %{count: 1, lag: lag},
      %{subscriber: to_string(key)}
    )
  end
end
