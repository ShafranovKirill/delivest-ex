defmodule Delivest.Integrations.YandexEda.BusyMode do
  use Ecto.Schema

  import Ecto.Query

  alias Delivest.Integrations.YandexEda.{Clock, PushApi}
  alias Delivest.Repo

  @primary_key {:branch_id, Ecto.UUID, autogenerate: false}

  schema "yandex_eda_busy_modes" do
    field :extra_minutes, :integer
    field :valid_till, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def active(branch_id) do
    now = DateTime.utc_now()
    Repo.one(from(b in __MODULE__, where: b.branch_id == ^branch_id and b.valid_till > ^now))
  end

  def sync(settings, branch_ids) do
    with {:ok, places} <- fetch(settings, branch_ids, nil, []) do
      rows = rows(places, branch_ids)
      {:ok, _} = replace(rows, branch_ids)
      {:ok, length(rows)}
    end
  end

  defp fetch(settings, branch_ids, cursor, acc) do
    filter =
      %{origin_ids: Enum.take(branch_ids, 100), limit: 500}
      |> then(&if cursor, do: Map.put(&1, :cursor, cursor), else: &1)

    with {:ok, %{"busy_places" => places} = body} <- PushApi.busy_places(settings, filter) do
      case body["cursor"] do
        cursor when is_binary(cursor) and cursor != "" and places != [] ->
          fetch(settings, branch_ids, cursor, acc ++ places)

        _done ->
          {:ok, acc ++ places}
      end
    end
  end

  defp rows(places, branch_ids) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    places
    |> Enum.filter(&(&1["origin_id"] in branch_ids))
    |> Enum.flat_map(fn place ->
      with minutes when is_integer(minutes) <- place["extra_minutes"],
           {:ok, till} <- Clock.parse(place["valid_till"]) do
        [%{branch_id: place["origin_id"], extra_minutes: minutes, valid_till: till}]
      else
        _skip -> []
      end
    end)
    |> Enum.group_by(& &1.branch_id)
    |> Enum.map(fn {_id, list} ->
      list |> Enum.max_by(& &1.extra_minutes) |> Map.merge(%{inserted_at: now, updated_at: now})
    end)
  end

  defp replace(rows, branch_ids) do
    Repo.transaction(fn ->
      Repo.delete_all(from(b in __MODULE__, where: b.branch_id in ^branch_ids))
      Repo.insert_all(__MODULE__, rows)
    end)
  end
end
