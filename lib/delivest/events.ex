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
    attrs = %{
      type: type,
      aggregate_type: aggregate_type(aggregate),
      aggregate_id: aggregate.id,
      branch_id: Map.get(aggregate, :branch_id),
      payload: Map.put_new(payload, :v, 1),
      actor: actor
    }

    repo.transaction(fn ->
      Ecto.Adapters.SQL.query!(
        repo,
        "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
        ["event_record:#{attrs.aggregate_type}:#{attrs.aggregate_id}"]
      )

      with {:ok, event} <- repo.insert(struct(Event, attrs)),
           :ok <- enqueue(repo, event) do
        event
      else
        {:error, reason} -> repo.rollback(reason)
      end
    end)
  end

  def list(aggregate_type, aggregate_id) do
    Event
    |> where([e], e.aggregate_type == ^aggregate_type and e.aggregate_id == ^aggregate_id)
    |> order_by([e], asc: e.sequence)
    |> Repo.all()
  end

  def list_blocked(staff, branch_id) do
    with :ok <- Identity.authorize(staff, "orders.update", branch_id) do
      Ecto.Adapters.SQL.query!(
        Repo,
        """
        WITH candidates AS (
          SELECT d.event_id, d.subscriber,
                 COALESCE(bool_or(j.state = 'completed'), false) AS completed,
                 min(e.sequence) AS sequence
          FROM event_deliveries d
          JOIN domain_events e ON e.id = d.event_id
          LEFT JOIN oban_jobs j
            ON j.worker = $2 AND j.args->>'event_id' = e.id::text
            AND j.args->>'subscriber' = d.subscriber
          WHERE e.branch_id = $1 AND d.status = 'pending'
          GROUP BY d.event_id, d.subscriber
          HAVING NOT COALESCE(bool_or(j.state IN ('available', 'scheduled', 'retryable', 'executing')), false)
          ORDER BY sequence
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
           order_by: [asc: e.sequence],
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
        lock_delivery(event, subscriber)

        delivery = Repo.get_by(Delivery, event_id: event_id, subscriber: subscriber)
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
              {:ok, _} =
                %{event_id: event_id, subscriber: subscriber}
                |> DeliverWorker.new()
                |> Oban.insert()

            %Oban.Job{} ->
              :ok = Oban.retry_job(job.id)
          end
        end

        updated =
          delivery
          |> Ecto.Changeset.change(
            status: if(action == "done", do: "delivered", else: "pending"),
            last_error: nil
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

  defp lock_delivery(event, subscriber) do
    Ecto.Adapters.SQL.query!(
      Repo,
      "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
      ["#{event.aggregate_type}:#{event.aggregate_id}:#{subscriber}"]
    )
  end

  defp enqueue(repo, %Event{} = event) do
    event.type
    |> Registry.listening()
    |> Enum.reduce_while(:ok, fn module, :ok ->
      key = to_string(module.key())

      with {:ok, _delivery} <- repo.insert(%Delivery{event_id: event.id, subscriber: key}),
           {:ok, _job} <-
             %{event_id: event.id, subscriber: key} |> DeliverWorker.new() |> Oban.insert() do
        {:cont, :ok}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp aggregate_type(%{__struct__: module}),
    do: module |> Module.split() |> List.last() |> Macro.underscore()
end
