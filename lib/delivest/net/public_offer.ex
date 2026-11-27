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
      is_combo: Map.get(product, :is_combo, false),
      tags: Map.get(product, :tags, []),
      suggested: Map.get(product, :suggested, false),
      popular: Map.get(product, :popular, false),
      photo_url: Map.get(product, :photo_url),
      photo_variants: Map.get(product, :photo_variants, []),
      stopped:
        MapSet.member?(stopped.products, product.id) or
          (Map.get(product, :is_combo, false) and
             (not Delivest.Net.ComboAvailability.valid_groups?(
                Map.get(stopped.groups, product.id, [])
              ) or
                Enum.any?(Map.get(stopped.groups, product.id, []), fn group ->
                  group.min == 1 and
                    Enum.all?(group.modifiers, fn modifier ->
                      MapSet.member?(stopped.modifiers, modifier.id) or
                        MapSet.member?(
                          Map.get(stopped, :unavailable_components, MapSet.new()),
                          modifier.component_product_id
                        )
                    end)
                end))),
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
            component_product_id: m.component_product_id,
            is_default: m.is_default,
            weight: m.weight,
            photo_url: Delivest.Net.Modifiers.photo_url(m),
            stopped:
              MapSet.member?(stopped.modifiers, m.id) or
                MapSet.member?(
                  Map.get(stopped, :unavailable_components, MapSet.new()),
                  m.component_product_id
                )
          }
        end
    }
  end
end
