defmodule Delivest.Net.Combos do
  @moduledoc "Authoring of component choices belonging to a menu combo."

  import Ecto.Query

  alias Delivest.{Identity, Money, Relations, Repo}
  alias Delivest.Net.{Modifier, ModifierGroup, Product, ProductModifierGroup, Products}
  alias Delivest.Net.SharedOwnership

  def load(nil), do: []

  def load(product_id) do
    from(link in ProductModifierGroup,
      join: group in ModifierGroup,
      on: group.id == link.group_id,
      where: link.product_id == ^product_id,
      order_by: link.position,
      preload: [group: {group, modifiers: ^from(m in Modifier, order_by: m.position)}]
    )
    |> Repo.all()
    |> Enum.map(fn link ->
      group = link.group

      %{
        name: group.name,
        required: group.min == 1,
        options:
          Enum.map(group.modifiers, fn modifier ->
            %{
              component_product_id: modifier.component_product_id,
              price: Money.input(modifier.price)
            }
          end)
      }
    end)
  end

  def options(branch_id, product_id) do
    ids = Relations.list_target_ids("Branch", branch_id, "Product")

    branch_id
    |> Products.list_branch_menu_products_by_ids(ids)
    |> Map.values()
    |> Enum.reject(&(&1.is_combo or &1.id == product_id))
    |> Enum.sort_by(&{&1.name, &1.id})
    |> Enum.map(&{&1.name, &1.id})
  end

  @doc "Replaces the private groups of a combo inside the product save transaction."
  def replace(staff, %Product{is_combo: true} = product, branch_id, groups) do
    with :ok <- Identity.authorize(staff, "products.update", branch_id),
         :ok <- SharedOwnership.authorize(staff, "products.update", "Product", product.id),
         {:ok, normalized} <- validate(groups, branch_id, product.id) do
      if same_groups?(product.id, normalized) do
        {:ok, product}
      else
        write_groups(product, normalized)
      end
    end
  end

  def replace(_staff, %Product{}, _branch_id, []), do: {:ok, :unchanged}
  def replace(_staff, %Product{}, _branch_id, _groups), do: {:error, :combo_not_enabled}

  def clear(staff, %Product{is_combo: true} = product, branch_id) do
    with :ok <- Identity.authorize(staff, "products.update", branch_id),
         :ok <- SharedOwnership.authorize(staff, "products.update", "Product", product.id) do
      old_ids =
        Repo.all(
          from(link in ProductModifierGroup,
            where: link.product_id == ^product.id,
            select: link.group_id
          )
        )

      Repo.delete_all(from(link in ProductModifierGroup, where: link.product_id == ^product.id))

      Enum.each(old_ids, fn group_id ->
        unless Repo.exists?(from(link in ProductModifierGroup, where: link.group_id == ^group_id)) do
          Repo.delete_all(from(m in Modifier, where: m.group_id == ^group_id))
          Repo.delete_all(from(g in ModifierGroup, where: g.id == ^group_id))
        end
      end)

      {:ok, product}
    end
  end

  defp same_groups?(product_id, groups) do
    current = load(product_id)

    projected =
      Enum.map(groups, fn group ->
        %{
          name: group.name,
          required: group.required,
          options:
            Enum.map(group.options, fn option ->
              %{
                component_product_id: option.component_product_id,
                price: Money.input(option.price)
              }
            end)
        }
      end)

    current == projected
  end

  defp write_groups(product, normalized) do
    old_ids =
      Repo.all(
        from(link in ProductModifierGroup,
          where: link.product_id == ^product.id,
          select: link.group_id
        )
      )

    Repo.delete_all(from(link in ProductModifierGroup, where: link.product_id == ^product.id))

    Enum.each(old_ids, fn group_id ->
      unless Repo.exists?(from(link in ProductModifierGroup, where: link.group_id == ^group_id)) do
        Repo.delete_all(from(m in Modifier, where: m.group_id == ^group_id))
        Repo.delete_all(from(g in ModifierGroup, where: g.id == ^group_id))
      end
    end)

    normalized
    |> Enum.with_index()
    |> Enum.each(fn {group, position} ->
      {:ok, saved_group} =
        %ModifierGroup{}
        |> ModifierGroup.changeset(%{
          name: group.name,
          min: if(group.required, do: 1, else: 0),
          max: 1,
          position: position
        })
        |> Repo.insert()

      Repo.insert!(%ProductModifierGroup{
        product_id: product.id,
        group_id: saved_group.id,
        position: position
      })

      group.options
      |> Enum.with_index()
      |> Enum.each(fn {option, option_position} ->
        %Modifier{}
        |> Modifier.changeset(%{
          group_id: saved_group.id,
          name: option.name,
          component_product_id: option.component_product_id,
          price: option.price,
          max_quantity: 1,
          position: option_position
        })
        |> Repo.insert!()
      end)
    end)

    {:ok, product}
  end

  defp validate(groups, branch_id, product_id) when is_list(groups) and groups != [] do
    available = options(branch_id, product_id) |> Map.new(fn {name, id} -> {id, name} end)

    Enum.reduce_while(groups, {:ok, []}, fn group, {:ok, acc} ->
      name = group |> Map.get("name", "") |> String.trim()
      required = Map.get(group, "required") in [true, "true", "on", "1"]
      options = Map.get(group, "options", [])

      with true <- name != "" and String.length(name) <= 100,
           true <- is_list(options) and options != [],
           {:ok, resolved} <- validate_options(options, available) do
        {:cont, {:ok, acc ++ [%{name: name, required: required, options: resolved}]}}
      else
        _ -> {:halt, {:error, :invalid_combo}}
      end
    end)
  end

  defp validate(_groups, _branch_id, _product_id), do: {:error, :invalid_combo}

  defp validate_options(options, available) do
    result =
      Enum.reduce_while(options, {:ok, []}, fn option, {:ok, acc} ->
        id = Map.get(option, "component_product_id")

        with name when is_binary(name) <- Map.get(available, id),
             {:ok, price} <- Money.parse(Map.get(option, "price", "0")),
             true <- price >= 0 do
          {:cont, {:ok, acc ++ [%{component_product_id: id, name: name, price: price}]}}
        else
          _ -> {:halt, {:error, :invalid_combo}}
        end
      end)

    case result do
      {:ok, parsed} ->
        if Enum.uniq_by(parsed, & &1.component_product_id) == parsed,
          do: result,
          else: {:error, :invalid_combo}

      error ->
        error
    end
  end
end
