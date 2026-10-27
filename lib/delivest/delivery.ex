defmodule Delivest.Delivery do
  import Ecto.Query

  alias Delivest.{Identity, Repo}
  alias Delivest.Delivery.{Quote, Settings, Zone}

  @palette ~w(#2563eb #16a34a #f59e0b #dc2626 #9333ea #0891b2 #db2777 #65a30d)

  def get_settings(branch_id),
    do: Repo.get_by(Settings, branch_id: branch_id) || %Settings{branch_id: branch_id}

  def change_settings(%Settings{} = settings, attrs \\ %{}),
    do: Settings.changeset(settings, attrs)

  def update_settings(staff, branch_id, attrs) do
    with :ok <- authorize(staff, branch_id) do
      branch_id
      |> get_settings()
      |> Settings.changeset(attrs)
      |> Repo.insert_or_update()
    end
  end

  def list_zones(branch_id) do
    from(z in Zone,
      where: z.branch_id == ^branch_id and is_nil(z.deleted_at),
      order_by: [asc: z.position, asc: z.inserted_at]
    )
    |> Repo.all()
  end

  def list_all_zones(branch_id) do
    from(z in Zone, where: z.branch_id == ^branch_id, order_by: [asc: z.position])
    |> Repo.all()
  end

  def get_zone(branch_id, id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Zone{} = zone <-
           Repo.one(
             from(z in Zone,
               where: z.id == ^uuid and z.branch_id == ^branch_id and is_nil(z.deleted_at)
             )
           ) do
      {:ok, zone}
    else
      _ -> {:error, :zone_not_found}
    end
  end

  def change_zone(%Zone{} = zone, attrs \\ %{}), do: Zone.changeset(zone, attrs)

  def create_zone(staff, branch_id, polygon) do
    with :ok <- authorize(staff, branch_id) do
      count = length(list_zones(branch_id))

      %Zone{
        branch_id: branch_id,
        name: "Зона #{count + 1}",
        color: Enum.at(@palette, rem(count, length(@palette))),
        position: count
      }
      |> Zone.polygon_changeset(polygon)
      |> Repo.insert()
    end
  end

  def update_zone(staff, branch_id, id, attrs) do
    with :ok <- authorize(staff, branch_id),
         {:ok, zone} <- get_zone(branch_id, id) do
      zone |> Zone.changeset(attrs) |> Repo.update()
    end
  end

  def update_zone_polygon(staff, branch_id, id, polygon) do
    with :ok <- authorize(staff, branch_id),
         {:ok, zone} <- get_zone(branch_id, id) do
      zone |> Zone.polygon_changeset(polygon) |> Repo.update()
    end
  end

  def delete_zone(staff, branch_id, id) do
    with :ok <- authorize(staff, branch_id),
         {:ok, zone} <- get_zone(branch_id, id) do
      zone
      |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second), enabled: false)
      |> Repo.update()
    end
  end

  def quote(branch_id, point, subtotal) do
    Quote.run(get_settings(branch_id), list_zones(branch_id), point, subtotal)
  end

  defp authorize(staff, branch_id) do
    if Identity.can?(staff, "branches.update") and Identity.has_branch_access?(staff, branch_id),
      do: :ok,
      else: {:error, :forbidden}
  end
end
