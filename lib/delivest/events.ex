defmodule Delivest.Events do
  import Ecto.Query

  alias Delivest.Events.{DeliverWorker, Delivery, Event, Registry}
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
