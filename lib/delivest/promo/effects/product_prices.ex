defmodule Delivest.Promo.Effects.ProductPrices do
  alias Delivest.Promo.{Basket, Compiled, Line}

  def apply(%Basket{} = basket, selected) do
    offers = offers_by_product(selected)
    {lines, credits} = Enum.map_reduce(basket.lines, [], &price_line(&1, &2, offers))

    Enum.reduce(credits, %{basket | lines: lines}, fn {promotion_id, amount}, acc ->
      Basket.credit(acc, promotion_id, amount)
    end)
  end

  def offers_by_product(selected),
    do: selected |> Enum.flat_map(&offers/1) |> Enum.group_by(&elem(&1, 0))

  def best(offers, base_price) do
    offers
    |> Enum.map(fn {_product_id, promotion_id, price} -> {price.(base_price), promotion_id} end)
    |> Enum.filter(fn {unit, _promotion_id} -> unit < base_price end)
    |> Enum.min_by(&elem(&1, 0), fn -> nil end)
  end

  defp price_line(%Line{gift: true} = line, credits, _offers), do: {line, credits}

  defp price_line(%Line{} = line, credits, offers) do
    case best(Map.get(offers, line.product_id, []), line.base_price) do
      nil ->
        {line, credits}

      {unit, promotion_id} ->
        amount = (line.base_price - unit) * line.quantity
        {Line.reduce(line, amount, promotion_id), [{promotion_id, amount} | credits]}
    end
  end

  defp offers(%Compiled{strategy: strategy} = compiled),
    do: Enum.flat_map(strategy.effects, &offer(&1, compiled))

  defp offer({:price, slug, price}, compiled),
    do: targeted(compiled, [slug], fn _base -> price end)

  defp offer({:percent, percent, {:products, slugs}, _cap}, compiled),
    do: targeted(compiled, slugs, &(&1 - div(&1 * percent, 100)))

  defp offer({:amount, amount, {:products, slugs}}, compiled),
    do: targeted(compiled, slugs, &max(&1 - amount, 0))

  defp offer(_effect, _compiled), do: []

  defp targeted(compiled, slugs, price) do
    slugs
    |> Enum.map(&Compiled.product_id(compiled, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&{&1, compiled.promotion.id, price})
  end
end
