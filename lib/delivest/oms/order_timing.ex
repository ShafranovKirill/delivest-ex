defmodule Delivest.Oms.OrderTiming do
  @moduledoc "Branch timing rules and a database-free calculation for an already priced cart."

  import Ecto.Query

  alias Delivest.{Identity, Intake, Repo}
  alias Delivest.Identity.Branch
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Oms.OrderTiming.Settings
  alias Delivest.Relations.EntityRelation

  @fixed_minutes 60

  def get(branch_id) do
    case Identity.get_branch(branch_id, preload: :info) do
      {:ok, %{info: %BranchInfo{timing: %Settings{} = settings}}} -> settings
      _ -> %Settings{}
    end
  end

  def fixed_minutes(branch_id) do
    case Identity.get_branch(branch_id, preload: :info) do
      {:ok, %{info: %BranchInfo{delivery_time: minutes}}}
      when is_integer(minutes) and minutes > 0 ->
        minutes

      _ ->
        @fixed_minutes
    end
  end

  def update(staff, branch_id, attrs), do: save(staff, branch_id, attrs, "branches.update")

  def update_delivery(staff, branch_id, attrs) do
    allowed = ~w(mode fixed_delivery_minutes travel_minutes)
    save(staff, branch_id, attrs |> stringify_keys() |> Map.take(allowed), "delivery.update")
  end

  defp save(staff, branch_id, attrs, permission) do
    with :ok <- Identity.authorize(staff, permission, branch_id) do
      attrs = stringify_keys(attrs)

      result =
        Repo.transaction(fn ->
          branch = Repo.one!(from b in Branch, where: b.id == ^branch_id, lock: "FOR UPDATE")

          info =
            Repo.one(from i in BranchInfo, where: i.branch_id == ^branch_id, lock: "FOR UPDATE") ||
              %BranchInfo{branch_id: branch.id}

          timing_attrs = Map.drop(attrs, ["fixed_delivery_minutes"])
          validate_overrides!(branch_id, timing_attrs)

          changes = %{"timing" => timing_attrs}

          changes =
            if Map.has_key?(attrs, "fixed_delivery_minutes"),
              do: Map.put(changes, "delivery_time", attrs["fixed_delivery_minutes"]),
              else: changes

          case info |> BranchInfo.changeset(changes) |> Repo.insert_or_update() do
            {:ok, saved} -> saved.timing || %Settings{}
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end)

      case result do
        {:ok, settings} ->
          Cachex.del(:branch_cache, branch_id)
          {:ok, settings}

        {:error, reason} ->
          {:error, reason}
      end
    else
      error -> error
    end
  end

  defp stringify_keys(attrs) when is_map(attrs),
    do: Map.new(attrs, fn {key, value} -> {to_string(key), value} end)

  defp validate_overrides!(branch_id, attrs) do
    Enum.each([{"category_minutes", "Category"}, {"product_minutes", "Product"}], fn
      {field, type} ->
        case Map.get(attrs, field) do
          values when is_map(values) and map_size(values) > 0 ->
            ids = Map.keys(values)

            unless Enum.all?(ids, &match?({:ok, _}, Ecto.UUID.cast(&1))),
              do: Repo.rollback(:invalid_timing_override)

            related =
              Repo.all(
                from r in EntityRelation,
                  where:
                    r.from_entity_type == "Branch" and r.from_id == ^branch_id and
                      r.to_entity_type == ^type and r.to_id in ^ids,
                  select: r.to_id
              )

            if MapSet.new(ids) != MapSet.new(related), do: Repo.rollback(:foreign_timing_override)

          _ ->
            :ok
        end
    end)
  end

  def prep_minutes(%Settings{} = settings, items, extra_minutes \\ 0) when is_list(items) do
    longest =
      items
      |> Enum.reject(&Map.get(&1, :unavailable, false))
      |> Enum.map(fn item ->
        product_id = Map.get(item, :product_id)
        category_id = Map.get(item, :category_id)

        Map.get(settings.product_minutes || %{}, product_id) ||
          Map.get(settings.category_minutes || %{}, category_id) || settings.kitchen_minutes
      end)
      |> Enum.max(fn -> settings.kitchen_minutes end)

    longest + settings.packing_minutes + max(extra_minutes, 0)
  end

  def cart_prep_minutes(branch_id, items) when is_binary(branch_id) and is_list(items) do
    settings = get(branch_id)
    extra = if settings.mode == :calculated, do: Intake.extra_minutes(branch_id), else: 0
    prep_minutes(settings, items, extra)
  end

  def estimate(
        branch_id,
        fulfillment,
        items,
        zone_minutes \\ nil,
        now \\ DateTime.utc_now(:second)
      ) do
    settings = get(branch_id)

    cond do
      settings.mode == :fixed ->
        total = fixed_minutes(branch_id)
        ready = max(20, round(total / 2))

        %{
          prep_minutes: if(fulfillment == :delivery, do: nil, else: ready),
          total_minutes: if(fulfillment == :delivery, do: total, else: ready),
          ready_at:
            if(fulfillment == :delivery, do: nil, else: DateTime.add(now, ready, :minute)),
          delivered_at:
            if(fulfillment == :delivery, do: DateTime.add(now, total, :minute), else: nil)
        }

      true ->
        prep = prep_minutes(settings, items, Intake.extra_minutes(branch_id))

        travel =
          if(is_integer(zone_minutes) and zone_minutes > 0,
            do: zone_minutes,
            else: settings.travel_minutes
          )

        %{
          prep_minutes: prep,
          total_minutes: if(fulfillment == :delivery, do: prep + travel, else: prep),
          ready_at: DateTime.add(now, prep, :minute),
          delivered_at:
            if(fulfillment == :delivery,
              do: DateTime.add(now, prep + travel, :minute),
              else: nil
            )
        }
    end
  end
end
