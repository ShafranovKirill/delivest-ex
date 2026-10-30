defmodule Delivest.Integrations.Inbox do
  import Ecto.Query

  alias Delivest.Integrations.Inbox.{Message, Worker}
  alias Delivest.Repo

  @handlers %{
    "frontpad" => Delivest.Integrations.Frontpad.Webhook,
    "iiko" => Delivest.Integrations.Iiko.Webhook
  }

  def handler(provider) do
    case Map.fetch(@handlers, to_string(provider)) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, :unknown_provider}
    end
  end

  def accept(provider, event_id, branch_id, payload) do
    row = %{
      id: Ecto.UUID.generate(version: 7),
      provider: to_string(provider),
      event_id: to_string(event_id),
      branch_id: branch_id,
      payload: payload,
      status: :pending,
      inserted_at: DateTime.utc_now()
    }

    Repo.transaction(fn ->
      case Repo.insert_all(Message, [row],
             on_conflict: :nothing,
             conflict_target: [:provider, :event_id]
           ) do
        {1, _rows} -> enqueue(row.id)
        {0, _rows} -> :duplicate
      end
    end)
  end

  def processed(%Message{} = message),
    do: change(message, status: :processed, error: nil, processed_at: DateTime.utc_now())

  def retrying(%Message{} = message, reason), do: change(message, error: inspect(reason))

  def failed(%Message{} = message, reason),
    do: change(message, status: :failed, error: inspect(reason))

  def list(provider, opts \\ []) do
    Message
    |> where([m], m.provider == ^to_string(provider))
    |> by_status(Keyword.get(opts, :status))
    |> order_by([m], desc: m.id)
    |> limit(^Keyword.get(opts, :limit, 50))
    |> Repo.all()
  end

  def prune(days) do
    cutoff = DateTime.add(DateTime.utc_now(), -days, :day)

    {count, _} =
      Message
      |> where([m], m.status != :pending and m.inserted_at < ^cutoff)
      |> Repo.delete_all()

    count
  end

  defp enqueue(id) do
    case %{id: id} |> Worker.new() |> Oban.insert() do
      {:ok, _job} -> :accepted
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp change(message, changes), do: message |> Ecto.Changeset.change(changes) |> Repo.update()

  defp by_status(query, nil), do: query
  defp by_status(query, status), do: where(query, [m], m.status == ^status)
end
