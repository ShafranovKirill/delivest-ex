defmodule Delivest.Net.ComboAvailability do
  @moduledoc "Checks branch availability of products selected as combo components."

  alias Delivest.Net.{Modifiers, Products, Stops}

  def unavailable_component_ids(branch_id, groups_by_product) do
    ids =
      groups_by_product
      |> Map.values()
      |> List.flatten()
      |> Enum.flat_map(& &1.modifiers)
      |> Enum.map(& &1.component_product_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if ids == [] do
      MapSet.new()
    else
      available = Products.list_branch_menu_products_by_ids(branch_id, ids)
      stopped = Stops.stopped_ids(branch_id)

      ids
      |> Enum.reject(fn id ->
        match?(%{is_combo: false}, available[id]) and not MapSet.member?(stopped, id)
      end)
      |> MapSet.new()
    end
  end

  def valid_groups?(groups) do
    groups != [] and
      Enum.all?(groups, fn group ->
        group.min in [0, 1] and group.max == 1 and group.modifiers != [] and
          Enum.all?(group.modifiers, fn modifier ->
            is_binary(modifier.component_product_id) and modifier.max_quantity == 1
          end)
      end)
  end

  def selected_available?(groups, choices, unavailable_ids) do
    valid_groups?(groups) and
      Enum.all?(groups, fn group ->
        count =
          Enum.count(choices, fn choice ->
            Enum.any?(group.modifiers, &(&1.id == choice.id))
          end)

        count >= group.min and count <= 1
      end) and
      Enum.all?(choices, fn choice ->
        Enum.any?(groups, fn group ->
          Enum.any?(group.modifiers, fn modifier ->
            modifier.id == choice.id and
              not MapSet.member?(unavailable_ids, modifier.component_product_id)
          end)
        end)
      end)
  end

  def explicitly_selected?(selection, choices) when is_list(selection) do
    requested =
      Enum.map(selection, fn
        id when is_binary(id) -> id
        %{"id" => id} -> id
        %{id: id} -> id
        _ -> nil
      end)

    Enum.sort(requested) == Enum.sort(Enum.map(choices, & &1.id))
  end

  def explicitly_selected?(_selection, choices), do: choices == []

  def unavailable_for_product(branch_id, product_id, choices) do
    groups = Map.get(Modifiers.for_products([product_id]), product_id, [])
    unavailable = unavailable_component_ids(branch_id, %{product_id => groups})
    not selected_available?(groups, choices, unavailable)
  end
end
