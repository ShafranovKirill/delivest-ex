defmodule Delivest.Events do
  import Ecto.Query

  alias Delivest.Events.{DeliverWorker, Event, Registry}
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

    with {:ok, event} <- repo.insert(struct(Event, attrs)),
         :ok <- enqueue(event) do
      {:ok, event}
    end
  end

  def list(aggregate_type, aggregate_id) do
    Event
    |> where([e], e.aggregate_type == ^aggregate_type and e.aggregate_id == ^aggregate_id)
    |> order_by([e], asc: e.id)
    |> Repo.all()
  end

  defp enqueue(%Event{} = event) do
    event.type
    |> Registry.listening()
    |> Enum.reduce_while(:ok, fn module, :ok ->
      %{event_id: event.id, subscriber: to_string(module.key())}
      |> DeliverWorker.new()
      |> Oban.insert()
      |> case do
        {:ok, _job} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp aggregate_type(%{__struct__: module}),
    do: module |> Module.split() |> List.last() |> Macro.underscore()
end
