defmodule Delivest.Integrations.YandexEda.MenuItem do
  alias Delivest.Media
  alias Delivest.Net.Product

  def build({category, product, index, price}, settings) do
    %{
      id: product.id,
      categoryId: category.id,
      name: product.name,
      price: price,
      measure: product.weight || 0,
      measureUnit: measure_unit(product.measure_unit),
      sortOrder: index,
      modifierGroups: []
    }
    |> put_optional(:description, product.description)
    |> put_optional(:images, images(product.media))
    |> put_optional(:nutrients, nutrients(product))
    |> put_optional(:excise, product.excise && to_string(product.excise))
    |> put_optional(:vat, settings.vat > 0 && settings.vat)
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
