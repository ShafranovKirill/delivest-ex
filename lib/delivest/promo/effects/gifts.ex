defmodule Delivest.Promo.Effects.Gifts do
  alias Delivest.Promo.{Basket, Compiled, Line}

  def apply(%Basket{} = basket, selected, choices \\ %{}),
    do: Basket.add_lines(basket, Enum.flat_map(selected, &gifts(&1, choices)))

  def choice(compiled, choices) do
    case Enum.find(compiled.strategy.effects, &match?({:gift_any, _, _}, &1)) do
      nil ->
        nil

      {:gift_any, slugs, count} ->
        products = Compiled.available_products(compiled, slugs)
        ids = Enum.map(products, & &1.id)

        selected =
          choices
          |> Map.get(compiled.promotion.id, [])
          |> Enum.filter(&(&1 in ids))
          |> Enum.uniq()
          |> Enum.take(count)

        %{
          required: count,
          available: length(products) >= count,
          selected: selected,
          options:
            Enum.map(products, fn product ->
              %{
                product_id: product.id,
                name: product.name,
                price: product.price,
                image_url: Delivest.Media.thumb_url_from_file(product.media)
              }
            end)
        }
    end
  end

  defp gifts(%Compiled{strategy: strategy} = compiled, choices),
    do: Enum.flat_map(strategy.effects, &gift(&1, compiled, choices))

  defp gift({:gift, slug, quantity}, compiled, _choices) do
    case Compiled.product(compiled, slug) do
      nil -> []
      product -> [Line.gift(product, quantity, compiled.promotion.id)]
    end
  end

  defp gift({:gift_any, _, _}, compiled, choices) do
    choice = choice(compiled, choices)

    if choice.available and length(choice.selected) == choice.required do
      for id <- choice.selected do
        product =
          Enum.find_value(compiled.products, fn {_, product} ->
            if product.id == id, do: product
          end)

        Line.gift(product, 1, compiled.promotion.id)
      end
    else
      []
    end
  end

  defp gift(_effect, _compiled, _choices), do: []
end
