defmodule Delivest.Net.PublicOffer do
  @moduledoc "Public product DTO shared by catalog projections."

  def data(product, stopped) do
    %{
      id: product.id,
      name: product.name,
      slug: Map.get(product, :slug),
      old_price: Map.get(product, :old_price),
      price: product.price,
      stars_reward: Map.get(stopped.rewards, product.id, Map.get(product, :stars_reward)),
      description: Map.get(product, :description),
      quantity: Map.get(product, :quantity),
      weight: Map.get(product, :weight),
      measure_unit: Map.get(product, :measure_unit, "g"),
      nutrition: Map.get(product, :nutrition),
      is_active: Map.get(product, :is_active),
      tags: Map.get(product, :tags, []),
      suggested: Map.get(product, :suggested, false),
      popular: Map.get(product, :popular, false),
      photo_url: Map.get(product, :photo_url),
      stopped: MapSet.member?(stopped.products, product.id),
      modifier_groups:
        for(group <- Map.get(stopped.groups, product.id, []), do: group_data(group, stopped))
    }
  end

  defp group_data(group, stopped) do
    %{
      id: group.id,
      name: group.name,
      min: group.min,
      max: group.max,
      is_size: group.is_size,
      modifiers:
        for m <- group.modifiers do
          %{
            id: m.id,
            name: m.name,
            price: m.price,
            max_quantity: m.max_quantity,
            is_default: m.is_default,
            weight: m.weight,
            photo_url: Delivest.Net.Modifiers.photo_url(m),
            stopped: MapSet.member?(stopped.modifiers, m.id)
          }
        end
    }
  end
end
