defmodule Delivest.Oms.Orders.Lines do
  alias Delivest.Net
  alias Delivest.Oms.CartView

  def from_cart(%CartView{items: items}) do
    products = Net.list_products_by_ids(Enum.map(items, & &1.product_id), preload: [:category])

    if Enum.all?(items, &Map.has_key?(products, &1.product_id)),
      do: {:ok, build(items, products)},
      else: {:error, :product_unavailable}
  end

  defp build(items, products) do
    lines = Enum.map(items, &line(&1, Map.fetch!(products, &1.product_id)))

    %{
      items: lines,
      total_amount: lines |> Enum.map(&(&1.price * &1.quantity)) |> Enum.sum()
    }
  end

  defp line(item, product) do
    %{
      product_id: product.id,
      title: product.name,
      price: product.price,
      quantity: item.quantity,
      category_id: product.category_id,
      category_name: category_name(product)
    }
  end

  defp category_name(%{category: %{name: name}}), do: name
  defp category_name(_product), do: nil
end
