defmodule DelivestWeb.Client.Menu.MenuJSON do
  def index(%{menu: categories, prepared: true}), do: %{data: categories}

  def index(%{menu: %{categories: categories}} = assigns),
    do: %{data: for(category <- categories, do: category_data(category, stopped(assigns)))}

  def index(%{menu: categories} = assigns) when is_list(categories),
    do: %{data: for(category <- categories, do: category_data(category, stopped(assigns)))}

  defp stopped(assigns) do
    %{
      products: Map.get(assigns, :stopped, MapSet.new()),
      modifiers: Map.get(assigns, :stopped_modifiers, MapSet.new()),
      groups: Map.get(assigns, :modifiers, %{}),
      rewards: Map.get(assigns, :rewards, %{}),
      popular: Map.get(assigns, :popular, MapSet.new())
    }
  end

  defp category_data(category, stopped) do
    %{
      id: category.id,
      name: category.name,
      order: Map.get(category, :order),
      is_active: Map.get(category, :is_active),
      products:
        for(
          product <- category.products || [],
          do: Delivest.Net.PublicOffer.data(product, stopped)
        )
    }
  end
end
