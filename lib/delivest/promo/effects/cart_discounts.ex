defmodule Delivest.Promo.Effects.CartDiscounts do
  alias Delivest.Money
  alias Delivest.Promo.{Basket, Compiled, Line}

  def apply(%Basket{} = basket, selected) do
    selected
    |> Enum.flat_map(&discounts/1)
    |> Enum.sort_by(&order/1)
    |> Enum.reduce(basket, &discount/2)
  end

  defp discounts(%Compiled{strategy: strategy, promotion: promotion}) do
    for effect <- strategy.effects, cart_wide?(effect), do: {promotion.id, effect}
  end

  defp cart_wide?({:percent, _percent, :cart, _cap}), do: true
  defp cart_wide?({:amount, _amount, :cart}), do: true
  defp cart_wide?(_effect), do: false

  defp order({_promotion_id, {:percent, _, _, _}}), do: 0
  defp order({_promotion_id, {:amount, _, _}}), do: 1

  defp discount({promotion_id, effect}, basket) do
    paid = Basket.paid(basket)
    amount = amount(effect, Basket.total(basket))
    shares = paid |> Enum.map(& &1.total) |> then(&Money.distribute(amount, &1))
    by_key = paid |> Enum.map(& &1.key) |> Enum.zip(shares) |> Map.new()

    %{basket | lines: Enum.map(basket.lines, &apply_share(&1, by_key, promotion_id))}
    |> Basket.credit(promotion_id, Enum.sum(shares))
  end

  defp apply_share(%Line{gift: true} = line, _by_key, _promotion_id), do: line

  defp apply_share(%Line{} = line, by_key, promotion_id) do
    case Map.get(by_key, line.key, 0) do
      0 -> line
      share -> Line.reduce(line, share, promotion_id)
    end
  end

  defp amount({:percent, percent, :cart, cap}, total),
    do: capped(Money.percent(total, percent), cap)

  defp amount({:amount, amount, :cart}, total), do: min(amount, total)

  defp capped(amount, nil), do: amount
  defp capped(amount, cap), do: min(amount, cap)
end
