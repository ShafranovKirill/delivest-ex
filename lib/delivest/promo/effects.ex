defmodule Delivest.Promo.Effects do
  alias Delivest.Promo.Basket
  alias Delivest.Promo.Effects.{CartDiscounts, Gifts, ProductPrices}

  def apply(%Basket{} = basket, selected) do
    basket
    |> ProductPrices.apply(selected)
    |> Gifts.apply(selected)
    |> CartDiscounts.apply(selected)
  end
end
