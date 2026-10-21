defmodule Delivest.Oms.Orders.Lines do
  alias Delivest.Net
  alias Delivest.Promo.{Allocation, Line, Result}

  def from_pricing(%Result{lines: lines, total: total}) do
    products = Net.list_products_by_ids(Enum.map(lines, & &1.product_id), preload: [:category])

    if Enum.all?(lines, &Map.has_key?(products, &1.product_id)),
      do: {:ok, %{items: Enum.flat_map(lines, &split(&1, products)), total_amount: total}},
      else: {:error, :product_unavailable}
  end

  defp split(%Line{} = line, products) do
    product = Map.fetch!(products, line.product_id)

    for {price, quantity} <- Allocation.split_unit_price(line.total, line.quantity) do
      %{
        product_id: product.id,
        title: product.name,
        price: price,
        base_price: line.base_price,
        gift: line.gift,
        quantity: quantity,
        category_id: product.category_id,
        category_name: category_name(product)
      }
    end
  end

  defp category_name(%{category: %{name: name}}), do: name
  defp category_name(_product), do: nil
end
