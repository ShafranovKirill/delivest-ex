defmodule Delivest.Net.ProductCopier do
  import Ecto.Query, warn: false

  alias Delivest.{Identity, Relations, Repo}
  alias Delivest.Net.{Categories, Product, Products}

  @copied_fields [
    :name,
    :price,
    :old_price,
    :description,
    :quantity,
    :weight,
    :media_id,
    :is_active
  ]

  def copy(staff, selection, from_branch_id, to_branch_id) do
    with :ok <- authorize(staff, from_branch_id, to_branch_id) do
      Repo.transaction(fn ->
        selection
        |> source_products(from_branch_id)
        |> Enum.map(&copy_product(staff, &1, to_branch_id))
        |> length()
      end)
    end
  end

  defp authorize(_staff, branch_id, branch_id), do: {:error, :same_branch}

  defp authorize(staff, from_branch_id, to_branch_id) do
    if Identity.can?(staff, "products.create") and
         Identity.has_branch_access?(staff, from_branch_id) and
         Identity.has_branch_access?(staff, to_branch_id),
       do: :ok,
       else: {:error, :forbidden}
  end

  defp source_products(selection, branch_id) do
    branch_product_ids = Relations.list_target_ids("Branch", branch_id, "Product")

    Product
    |> where([p], p.id in ^branch_product_ids and is_nil(p.deleted_at))
    |> select_ids(selection)
    |> order_by([p], asc: p.name)
    |> preload(:category)
    |> Repo.all()
  end

  defp select_ids(query, :all), do: query
  defp select_ids(query, ids) when is_list(ids), do: where(query, [p], p.id in ^ids)

  defp copy_product(staff, product, to_branch_id) do
    with {:ok, category} <- target_category(staff, product, to_branch_id),
         {:ok, copy} <- Products.create_product(staff, to_branch_id, attrs(product, category)) do
      copy
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp target_category(_staff, %Product{category: nil}, _branch_id), do: {:ok, nil}

  defp target_category(staff, %Product{category: category}, branch_id),
    do: Categories.find_or_create_category_by_name(staff, branch_id, category.name)

  defp attrs(product, category) do
    product
    |> Map.take(@copied_fields)
    |> Map.put(:category_id, category && category.id)
  end
end
