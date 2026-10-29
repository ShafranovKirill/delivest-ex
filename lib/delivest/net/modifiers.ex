defmodule Delivest.Net.Modifiers do
  import Ecto.Query

  alias Delivest.{Audit, Identity, Repo}
  alias Delivest.Net.{Modifier, ModifierGroup, ModifierStop, ProductModifierGroup}

  @type choice :: %{
          id: binary(),
          group_name: String.t(),
          name: String.t(),
          price: non_neg_integer(),
          quantity: pos_integer()
        }

  def list_groups do
    ModifierGroup
    |> order_by([g], asc: g.position, asc: g.name)
    |> preload(:modifiers)
    |> Repo.all()
  end

  def get_group(id), do: ModifierGroup |> Repo.get(id) |> Repo.preload(:modifiers)

  def change_group(%ModifierGroup{} = group, attrs \\ %{}),
    do: ModifierGroup.changeset(group, attrs)

  def save_group(staff, %ModifierGroup{} = group, attrs) do
    with :ok <- authorize(staff) do
      group
      |> ModifierGroup.changeset(attrs)
      |> Repo.insert_or_update()
      |> Audit.track(staff, "modifier_group.saved")
    end
  end

  def delete_group(staff, %ModifierGroup{} = group) do
    with :ok <- authorize(staff) do
      group |> Repo.delete() |> Audit.track(staff, "modifier_group.deleted")
    end
  end

  def change_modifier(%Modifier{} = modifier, attrs \\ %{}),
    do: Modifier.changeset(modifier, attrs)

  def save_modifier(staff, %Modifier{} = modifier, attrs) do
    with :ok <- authorize(staff) do
      modifier |> Modifier.changeset(attrs) |> Repo.insert_or_update()
    end
  end

  def delete_modifier(staff, %Modifier{} = modifier) do
    with :ok <- authorize(staff), do: Repo.delete(modifier)
  end

  def get_modifier(id), do: Repo.get(Modifier, id)

  def group_ids(product_id) do
    Repo.all(
      from(l in ProductModifierGroup,
        where: l.product_id == ^product_id,
        order_by: [asc: l.position],
        select: l.group_id
      )
    )
  end

  def attach(staff, product_id, group_ids) do
    with :ok <- authorize(staff) do
      rows =
        group_ids
        |> Enum.uniq()
        |> Enum.with_index()
        |> Enum.map(fn {group_id, index} ->
          %{product_id: product_id, group_id: group_id, position: index}
        end)

      Repo.transaction(fn ->
        Repo.delete_all(from(l in ProductModifierGroup, where: l.product_id == ^product_id))
        Repo.insert_all(ProductModifierGroup, rows)
        rows
      end)
    end
  end

  def for_products(product_ids) do
    links =
      Repo.all(
        from(l in ProductModifierGroup,
          join: g in assoc(l, :group),
          where: l.product_id in ^product_ids and g.is_active,
          order_by: [asc: l.position],
          preload: [group: {g, modifiers: ^from(m in Modifier, where: m.is_active)}]
        )
      )

    links
    |> Enum.group_by(& &1.product_id, & &1.group)
    |> Map.new(fn {product_id, groups} ->
      {product_id, Enum.reject(groups, &(&1.modifiers == []))}
    end)
  end

  def stopped_ids(branch_id, now \\ DateTime.utc_now()) do
    Repo.all(
      from(s in ModifierStop,
        where: s.branch_id == ^branch_id and (is_nil(s.until) or s.until > ^now),
        select: s.modifier_id
      )
    )
    |> MapSet.new()
  end

  def stop(staff, branch_id, %Modifier{} = modifier, period) do
    with :ok <- Identity.authorize(staff, "stops.update", branch_id) do
      %ModifierStop{
        modifier_id: modifier.id,
        branch_id: branch_id,
        until: Delivest.Net.StopPeriod.until(period, DateTime.utc_now(), branch_id),
        staff_id: staff.id
      }
      |> Repo.insert(
        on_conflict: {:replace, [:until, :staff_id, :updated_at]},
        conflict_target: [:modifier_id, :branch_id]
      )
    end
  end

  def resume(staff, branch_id, %Modifier{} = modifier) do
    with :ok <- Identity.authorize(staff, "stops.update", branch_id) do
      Repo.delete_all(
        from(s in ModifierStop,
          where: s.branch_id == ^branch_id and s.modifier_id == ^modifier.id
        )
      )

      :ok
    end
  end

  @spec resolve([ModifierGroup.t()], term(), MapSet.t()) ::
          {:ok, [choice()]} | {:error, atom()}
  def resolve(groups, selection, stopped \\ MapSet.new()) do
    picked = normalize(selection)
    known = for g <- groups, m <- g.modifiers, into: %{}, do: {m.id, {g, m}}

    cond do
      Enum.any?(picked, fn {id, _q} -> not Map.has_key?(known, id) end) ->
        {:error, :modifier_unavailable}

      Enum.any?(picked, fn {id, _q} -> MapSet.member?(stopped, id) end) ->
        {:error, :modifier_unavailable}

      true ->
        groups
        |> Enum.map(&pick(&1, picked, stopped))
        |> collect()
    end
  end

  def key(choices) do
    choices
    |> Enum.map(&"#{&1.id}*#{&1.quantity}")
    |> Enum.sort()
    |> Enum.join(",")
  end

  def price(choices), do: choices |> Enum.map(&(&1.price * &1.quantity)) |> Enum.sum()

  defp pick(group, picked, stopped) do
    chosen =
      for m <- group.modifiers, quantity = Map.get(picked, m.id), quantity > 0, do: {m, quantity}

    chosen =
      if chosen == [] and (picked == %{} or group.min > 0),
        do:
          for(m <- group.modifiers, m.is_default, not MapSet.member?(stopped, m.id), do: {m, 1}),
        else: chosen

    count = chosen |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    cond do
      Enum.any?(chosen, fn {m, quantity} -> quantity > m.max_quantity end) ->
        {:error, :modifier_quantity}

      count < group.min ->
        {:error, :modifiers_required}

      count > group.max ->
        {:error, :modifiers_limit}

      true ->
        {:ok, Enum.map(chosen, fn {m, quantity} -> choice(group, m, quantity) end)}
    end
  end

  defp choice(group, modifier, quantity) do
    %{
      id: modifier.id,
      group_name: group.name,
      name: modifier.name,
      price: modifier.price,
      quantity: quantity
    }
  end

  defp collect(results) do
    Enum.reduce_while(results, {:ok, []}, fn
      {:ok, choices}, {:ok, acc} -> {:cont, {:ok, acc ++ choices}}
      error, _acc -> {:halt, error}
    end)
  end

  defp normalize(nil), do: %{}

  defp normalize(selection) when is_list(selection) do
    Enum.reduce(selection, %{}, fn
      %{"id" => id} = item, acc ->
        Map.update(acc, id, quantity(item["quantity"]), &(&1 + quantity(item["quantity"])))

      %{id: id} = item, acc ->
        Map.update(acc, id, quantity(item[:quantity]), &(&1 + quantity(item[:quantity])))

      id, acc when is_binary(id) ->
        Map.update(acc, id, 1, &(&1 + 1))

      _other, acc ->
        acc
    end)
  end

  defp normalize(_selection), do: %{}

  defp quantity(value) when is_integer(value) and value > 0, do: value
  defp quantity(nil), do: 1
  defp quantity(_value), do: 0

  defp authorize(staff) do
    if Identity.can?(staff, "products.update"), do: :ok, else: {:error, :forbidden}
  end
end
