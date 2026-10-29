defmodule Delivest.Integrations.YandexEda.MenuItem do
  alias Delivest.{Media, Money}
  alias Delivest.Net.Product

  def build({category, product, index, price}, settings, groups \\ %{}) do
    %{
      id: product.id,
      categoryId: category.id,
      name: product.name,
      price: Money.to_rubles(price),
      measure: product.weight || 0,
      measureUnit: measure_unit(product.measure_unit),
      sortOrder: index,
      modifierGroups: groups |> Map.get(product.id, []) |> Enum.with_index() |> Enum.map(&group/1)
    }
    |> put_optional(:description, product.description)
    |> put_optional(:images, images(product.media))
    |> put_optional(:nutrients, nutrients(product))
    |> put_optional(:excise, product.excise && to_string(product.excise))
    |> put_optional(:vat, settings.vat > 0 && settings.vat)
  end

  defp group({group, index}) do
    %{
      id: group.id,
      name: group.name,
      minSelectedModifiers: group.min,
      maxSelectedModifiers: group.max,
      sortOrder: index,
      modifiers:
        Enum.map(group.modifiers, fn modifier ->
          %{
            id: modifier.id,
            name: modifier.name,
            price: Money.to_rubles(modifier.price),
            minAmount: 0,
            maxAmount: modifier.max_quantity
          }
        end)
    }
  end

  defp measure_unit(:ml), do: "мл"
  defp measure_unit(_unit), do: "г"

  defp images(%Media.File{key: key} = file) do
    case Media.get_url_from_file(file) do
      nil -> nil
      url -> [%{hash: :crypto.hash(:sha, key) |> Base.encode16(case: :lower), url: url}]
    end
  end

  defp images(_media), do: nil

  defp nutrients(product) do
    values = Map.take(product, Product.nutrients())
    if Enum.all?(values, fn {_field, value} -> is_number(value) end), do: values
  end

  defp put_optional(map, _key, value) when value in [nil, false, ""], do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)
end
