defmodule DelivestWeb.Client.Menu.MenuJSON do
  def index(%{menu: %{categories: categories}}) do
    %{data: for(category <- categories, do: category_data(category))}
  end

  def index(%{menu: categories}) when is_list(categories) do
    %{data: for(category <- categories, do: category_data(category))}
  end

  defp category_data(category) do
    %{
      id: category.id,
      name: category.name,
      order: Map.get(category, :order),
      is_active: Map.get(category, :is_active),
      products: for(product <- category.products || [], do: product_data(product))
    }
  end

  defp product_data(product) do
    %{
      id: product.id,
      name: product.name,
      old_price: Map.get(product, :old_price),
      price: product.price,
      description: Map.get(product, :description),
      quantity: Map.get(product, :quantity),
      weight: Map.get(product, :weight),
      is_active: Map.get(product, :is_active),
      photo_url: Map.get(product, :photo_url),
      external_id: Map.get(product, :external_id)
    }
  end
end
