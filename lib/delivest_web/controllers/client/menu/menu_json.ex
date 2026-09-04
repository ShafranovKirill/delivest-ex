defmodule DelivestWeb.Client.Menu.MenuJSON do
  def index(%{menu: categories}) do
    %{data: for(category <- categories, do: category_data(category))}
  end

  defp category_data(category) do
    %{
      id: category.id,
      name: category.name,
      order: category.order,
      is_active: category.is_active,
      products: for(product <- category.products || [], do: product_data(product))
    }
  end

  defp product_data(product) do
    %{
      id: product.id,
      name: product.name,
      old_price: product.old_price,
      price: product.price,
      description: product.description,
      quantity: product.quantity,
      weight: product.weight,
      is_active: product.is_active,
      media_id: product.media_id,
      external_id: product.external_id
    }
  end
end
