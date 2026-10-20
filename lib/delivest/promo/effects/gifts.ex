defmodule Delivest.Promo.Effects.Gifts do
  alias Delivest.Promo.{Basket, Compiled, Line}

  def apply(%Basket{} = basket, selected),
    do: Basket.add_lines(basket, Enum.flat_map(selected, &gifts/1))

  defp gifts(%Compiled{strategy: strategy} = compiled),
    do: Enum.flat_map(strategy.effects, &gift(&1, compiled))

  defp gift({:gift, slug, quantity}, compiled) do
    case Compiled.product(compiled, slug) do
      nil -> []
      product -> [Line.gift(product, quantity, compiled.promotion.id)]
    end
  end

  defp gift(_effect, _compiled), do: []
end
