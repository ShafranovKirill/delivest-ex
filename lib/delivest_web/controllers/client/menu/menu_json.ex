defmodule DelivestWeb.Client.Menu.MenuJSON do
  def index(%{menu: %{categories: categories}} = assigns),
    do: %{data: for(category <- categories, do: category_data(category, stopped(assigns)))}

  def index(%{menu: categories} = assigns) when is_list(categories),
    do: %{data: for(category <- categories, do: category_data(category, stopped(assigns)))}

  defp stopped(assigns), do: Map.get(assigns, :stopped, MapSet.new())

  defp category_data(category, stopped) do
    %{
      id: category.id,
      name: category.name,
      order: Map.get(category, :order),
      is_active: Map.get(category, :is_active),
      products: for(product <- category.products || [], do: product_data(product, stopped))
    }
  end

  defp product_data(product, stopped) do
    %{
      id: product.id,
      name: product.name,
      slug: Map.get(product, :slug),
      old_price: Map.get(product, :old_price),
      price: product.price,
      description: Map.get(product, :description),
      quantity: Map.get(product, :quantity),
      weight: Map.get(product, :weight),
      measure_unit: Map.get(product, :measure_unit, "g"),
      is_active: Map.get(product, :is_active),
      tags: Map.get(product, :tags, []),
      suggested: Map.get(product, :suggested, false),
      photo_url: Map.get(product, :photo_url),
      stopped: MapSet.member?(stopped, product.id)
    }
  end
end
