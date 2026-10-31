defmodule Delivest.Net.MenuExport do
  import Ecto.Query

  alias Delivest.{Identity, Money, Relations, Repo}
  alias Delivest.Integrations.Crm
  alias Delivest.Net.{Product, ProductCrmIds}

  @bom <<0xEF, 0xBB, 0xBF>>
  @delimiter ";"
  @header ["Название", "Цена", "Вес, г", "Штук", "Категория", "CRM ID", "Описание", "Активен"]

  def csv(staff, branch_id) do
    with :ok <- Identity.authorize(staff, "products.read", branch_id) do
      {:ok, @bom <> encode([@header | rows(branch_id)])}
    end
  end

  def filename(branch), do: "menu-#{branch.slug}.csv"

  defp rows(branch_id) do
    products = products(branch_id)

    crm_ids =
      ProductCrmIds.by_product(Enum.map(products, & &1.id), Crm.default_provider(branch_id))

    Enum.map(products, fn product ->
      [
        product.name,
        Money.input(product.price),
        product.weight,
        product.quantity,
        product.category && product.category.name,
        Map.get(crm_ids, product.id),
        product.description,
        if(product.is_active, do: "да", else: "нет")
      ]
    end)
  end

  defp products(branch_id) do
    ids = Relations.list_target_ids("Branch", branch_id, "Product")

    Product
    |> where([p], p.id in ^ids and is_nil(p.deleted_at))
    |> order_by([p], asc: p.name)
    |> preload(:category)
    |> Repo.all()
  end

  defp encode(rows),
    do: Enum.map_join(rows, "\r\n", &Enum.map_join(&1, @delimiter, fn cell -> cell(cell) end))

  defp cell(nil), do: ""

  defp cell(value) do
    text = to_string(value)

    if String.contains?(text, [@delimiter, "\"", "\n", "\r"]),
      do: "\"" <> String.replace(text, "\"", "\"\"") <> "\"",
      else: text
  end
end
