defmodule Delivest.Events do
  import Ecto.Query

  alias Delivest.Audit
  alias Delivest.Events.{DeliverWorker, Delivery, Event, Registry}
  alias Delivest.Identity
  alias Delivest.Oms.Order
  alias Delivest.Repo
  alias Ecto.Multi

  def emit(%Multi{} = multi, name, fun) when is_function(fun, 1) do
    Multi.run(multi, name, fn repo, changes ->
      case fun.(changes) do
        nil -> {:ok, nil}
        {type, aggregate, payload, actor} -> record(repo, type, aggregate, payload, actor)
      end
    end)
  end

  def record(repo \\ Repo, type, aggregate, payload, actor) do
    case repo.transaction(fn ->
           attrs = %{
             type: type,
             aggregate_type: aggregate_type(aggregate),
             aggregate_id: aggregate.id,
             sequence: next_sequence(repo, aggregate_type(aggregate), aggregate.id),
             branch_id: Map.get(aggregate, :branch_id),
             payload: Map.put_new(payload, :v, 1),
             actor: actor
           }

           event = repo.insert!(struct(Event, attrs))
           subscribers = Registry.listening(type) |> Enum.map(&to_string(&1.key()))
           now = DateTime.utc_now()

           rows =
             Enum.map(subscribers, fn key ->
               %{
                 event_id: event.id,
                 subscriber: key,
                 status: "pending",
                 inserted_at: now,
                 updated_at: now
               }
             end)

           if rows != [], do: repo.insert_all(Delivery, rows)

           # Every job targets this newly inserted event and its unique delivery row.
           # This producer cannot collide with an older job, so bulk insert is safe here;
           # manual retries still use Oban.insert/1 to enforce uniqueness.
           jobs =
             Enum.map(subscribers, fn key ->
               DeliverWorker.new(%{event_id: event.id, subscriber: key}, queue: queue(key))
             end)

           if jobs != [] and length(Oban.insert_all(jobs)) != length(jobs),
             do: repo.rollback(:incomplete_event_jobs)

           event
         end) do
      {:ok, event} -> {:ok, event}
      {:error, reason} -> {:error, reason}
    end
  end

  def list(aggregate_type, aggregate_id) do
    Event
    |> where([e], e.aggregate_type == ^aggregate_type and e.aggregate_id == ^aggregate_id)
    |> order_by([e], asc: e.sequence)
    |> Repo.all()
  end

  def list_blocked(staff, branch_id) do
    with :ok <- Identity.authorize(staff, "orders.update", branch_id) do
      Repo.query!(
        """
        WITH candidates AS (
          SELECT d.event_id, d.subscriber,
                 COALESCE(bool_or(j.state = 'completed'), false) AS completed
          FROM event_deliveries d
          JOIN domain_events e ON e.id = d.event_id
          LEFT JOIN oban_jobs j
            ON j.worker = $2 AND j.args->>'event_id' = e.id::text
            AND j.args->>'subscriber' = d.subscriber
          WHERE e.branch_id = $1 AND d.status = 'pending'
          GROUP BY d.event_id, d.subscriber
          HAVING NOT COALESCE(bool_or(j.state IN ('available', 'scheduled', 'retryable', 'executing')), false)
          LIMIT 100
        )
        UPDATE event_deliveries d
        SET status = CASE WHEN c.completed THEN 'delivered' ELSE 'blocked' END,
            last_error = CASE WHEN c.completed THEN NULL ELSE 'Delivery job stopped or was pruned' END,
            updated_at = now()
        FROM candidates c
        WHERE d.event_id = c.event_id AND d.subscriber = c.subscriber AND d.status = 'pending'
        """,
        [Ecto.UUID.dump!(branch_id), Oban.Worker.to_string(DeliverWorker)]
      )

      {:ok,
       Repo.all(
         from(d in Delivery,
           join: e in Event,
           on: e.id == d.event_id,
           where: e.branch_id == ^branch_id and d.status == "blocked",
           order_by: [asc: e.inserted_at, asc: e.sequence],
           limit: 100,
           select: %{
             event_id: d.event_id,
             subscriber: d.subscriber,
             last_error: d.last_error,
             updated_at: d.updated_at,
             aggregate_id: e.aggregate_id
           }
         )
       )}
    end
  end

  def resolve_delivery(staff, branch_id, event_id, subscriber, action)
      when action in ["retry", "done"] do
    with :ok <- Identity.authorize(staff, "orders.update", branch_id),
         {:ok, uuid} <- Ecto.UUID.cast(event_id),
         %Event{branch_id: ^branch_id} = event <- Repo.get(Event, uuid) do
      Repo.transaction(fn ->
        Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
          "#{event.aggregate_type}:#{event.aggregate_id}:#{subscriber}"
        ])

        delivery = Repo.get_by(Delivery, event_id: uuid, subscriber: subscriber)
        if is_nil(delivery) or delivery.status != "blocked", do: Repo.rollback(:not_blocked)

        if action == "retry" do
          job =
            Repo.one(
              from(j in Oban.Job,
                where: j.worker == ^Oban.Worker.to_string(DeliverWorker),
                where: fragment("?->>'event_id' = ?", j.args, ^event_id),
                where: fragment("?->>'subscriber' = ?", j.args, ^subscriber),
                order_by: [desc: j.id],
                limit: 1
              )
            )

          case job do
            nil ->
              %{event_id: event_id, subscriber: subscriber}
              |> DeliverWorker.new(queue: queue(subscriber))
              |> Oban.insert!()

            %Oban.Job{} ->
              :ok = Oban.retry_job(job.id)
          end
        end

        updated =
          delivery
          |> Ecto.Changeset.change(
            status: if(action == "done", do: "resolved", else: "pending"),
            last_error: nil,
            resolved_at: DateTime.utc_now()
          )
          |> Repo.update!()

        if order = Repo.get(Order, event.aggregate_id),
          do:
            Audit.record(staff, "order.event_delivery_resolved", order,
              metadata: %{event_id: event_id, subscriber: subscriber, action: action}
            )

        updated
      end)
    else
      :error -> {:error, :invalid_event_id}
      nil -> {:error, :event_not_found}
      %Event{} -> {:error, :event_not_found}
      error -> error
    end
  end

  def resolve_delivery(_staff, _branch_id, _event_id, _subscriber, _action),
    do: {:error, :invalid_action}

  defp next_sequence(repo, type, id) do
    %{rows: [[sequence]]} =
      repo.query!(
        """
        INSERT INTO event_sequences (aggregate_type, aggregate_id, value) VALUES ($1, $2, 1)
        ON CONFLICT (aggregate_type, aggregate_id)
        DO UPDATE SET value = event_sequences.value + 1
        RETURNING value
        """,
        [type, Ecto.UUID.dump!(id)]
      )

    sequence
  end

  defp aggregate_type(%{__struct__: module}),
    do: module |> Module.split() |> List.last() |> Macro.underscore()

  def queue("payments"), do: :payments
  def queue(_subscriber), do: :events
end
