defmodule Delivest.Delivery do
  import Ecto.Query

  alias Delivest.{Audit, Identity, Repo}
  alias Delivest.Delivery.{Quote, Settings, Zone}
  alias Delivest.Identity.Branch

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
      order_by: [asc: z.position, asc: z.inserted_at, asc: z.id]
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

  def list_public_zones(branch_id) do
    case get_settings(branch_id) do
      %Settings{mode: :zones, show_zones: true} ->
        Enum.filter(list_zones(branch_id), & &1.enabled)

      _settings ->
        []
    end
  end

  def branch_point(branch_id) do
    case Identity.get_branch(branch_id, preload: [:info]) do
      {:ok, %{info: %{latitude: lat, longitude: lng}}} when is_number(lat) and is_number(lng) ->
        {lat, lng}

      _ ->
        nil
    end
  end

  def create_zone(staff, branch_id, polygon) do
    with :ok <- authorize(staff, branch_id) do
      insert_first_zone(staff, branch_id, fn zone -> Zone.polygon_changeset(zone, polygon) end)
    end
  end

  def create_radius_zone(staff, branch_id, radius) do
    with :ok <- authorize(staff, branch_id),
         {lat, _lng} = center when is_number(lat) <-
           branch_point(branch_id) || {:error, :no_branch_point} do
      insert_first_zone(staff, branch_id, fn zone ->
        zone
        |> Zone.radius_changeset(center, radius)
        |> Ecto.Changeset.put_change(:name, "#{zone.name} · #{radius} км")
      end)
    end
  end

  def reorder_zones(staff, branch_id, ids) do
    with :ok <- authorize(staff, branch_id),
         true <- is_list(ids) and Enum.all?(ids, &is_binary/1) do
      Repo.transaction(fn ->
        branch = lock_branch(branch_id)
        zones = list_zones(branch_id)
        current_ids = Enum.map(zones, & &1.id)

        if length(ids) != length(current_ids) or MapSet.new(ids) != MapSet.new(current_ids) do
          Repo.rollback(:invalid_zone_order)
        end

        zones_by_id = Map.new(zones, &{&1.id, &1})

        Enum.each(Enum.with_index(ids), fn {id, position} ->
          zones_by_id
          |> Map.fetch!(id)
          |> Ecto.Changeset.change(position: position)
          |> Repo.update!()
        end)

        Audit.record(staff, "delivery.zones_reordered", branch, metadata: %{zone_ids: ids})
        list_zones(branch_id)
      end)
    else
      false -> {:error, :invalid_zone_order}
      error -> error
    end
  end

  def update_zone(staff, branch_id, id, attrs) do
    with :ok <- authorize(staff, branch_id),
         {:ok, zone} <- get_zone(branch_id, id) do
      zone |> resize(branch_id, attrs) |> Zone.changeset(attrs) |> Repo.update()
    end
  end

  def update_zone_polygon(staff, branch_id, id, polygon) do
    with :ok <- authorize(staff, branch_id),
         {:ok, zone} <- get_zone(branch_id, id) do
      zone
      |> Zone.polygon_changeset(polygon)
      |> Ecto.Changeset.put_change(:radius_km, nil)
      |> Repo.update()
    end
  end

  def delete_zone(staff, branch_id, id) do
    with :ok <- authorize(staff, branch_id) do
      Repo.transaction(fn ->
        lock_branch(branch_id)

        case get_zone(branch_id, id) do
          {:ok, zone} ->
            case zone
                 |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second), enabled: false)
                 |> Repo.update() do
              {:ok, deleted} -> deleted
              {:error, changeset} -> Repo.rollback(changeset)
            end

          {:error, reason} ->
            Repo.rollback(reason)
        end
      end)
    end
  end

  def quote(branch_id, point, subtotal) do
    Quote.run(get_settings(branch_id), list_zones(branch_id), point, subtotal)
  end

  def check(branch_id, point, subtotal) do
    settings = get_settings(branch_id)
    zones = list_zones(branch_id)

    case Quote.run(settings, zones, point, subtotal) do
      {:ok, quote} ->
        quote_fields(quote) |> Map.put(:status, :ok)

      {:error, {:below_minimum, min_order}} ->
        {:ok, quote} = Quote.run(settings, zones, point, min_order)

        quote
        |> quote_fields()
        |> Map.put(:status, :below_minimum)

      {:error, reason} ->
        %{
          status: reason,
          price: nil,
          min_order: nil,
          free_from: nil,
          minutes: nil,
          zone_id: nil,
          zone_name: nil,
          zone_color: nil
        }
    end
  end

  defp quote_fields(quote) do
    quote
    |> Map.take([:price, :min_order, :free_from, :minutes])
    |> Map.merge(%{
      zone_id: quote.zone && quote.zone.id,
      zone_name: quote.zone && quote.zone.name,
      zone_color: quote.zone && quote.zone.color
    })
  end

  defp insert_first_zone(staff, branch_id, changeset_fun) do
    Repo.transaction(fn ->
      branch = lock_branch(branch_id)
      zones = list_zones(branch_id)
      zone = new_zone(branch_id, length(zones))
      changeset = changeset_fun.(zone)

      if not changeset.valid?, do: Repo.rollback(changeset)

      Enum.each(Enum.with_index(zones, 1), fn {existing, position} ->
        existing |> Ecto.Changeset.change(position: position) |> Repo.update!()
      end)

      case Repo.insert(changeset) do
        {:ok, inserted} ->
          Audit.record(staff, "delivery.zone_created", branch, metadata: %{zone_id: inserted.id})
          inserted

        {:error, invalid} ->
          Repo.rollback(invalid)
      end
    end)
  end

  defp lock_branch(branch_id),
    do: Repo.one!(from(b in Branch, where: b.id == ^branch_id, lock: "FOR UPDATE"))

  defp new_zone(branch_id, count) do
    %Zone{
      branch_id: branch_id,
      name: "Зона #{count + 1}",
      color: Enum.at(@palette, rem(count, length(@palette))),
      position: 0
    }
  end

  defp resize(%Zone{radius_km: radius} = zone, branch_id, %{"radius_km" => value})
       when is_number(radius) and value not in [nil, ""] do
    case branch_point(branch_id) do
      nil -> Ecto.Changeset.change(zone)
      center -> Zone.radius_changeset(zone, center, value)
    end
  end

  defp resize(zone, _branch_id, _attrs), do: Ecto.Changeset.change(zone)

  defp authorize(staff, branch_id) do
    Identity.authorize(staff, "delivery.update", branch_id)
  end
end
