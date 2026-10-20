defmodule Delivest.Promo.Allocation do
  @spec distribute(non_neg_integer(), [non_neg_integer()]) :: [non_neg_integer()]
  def distribute(amount, weights) do
    case Enum.sum(weights) do
      0 -> Enum.map(weights, fn _ -> 0 end)
      total -> largest_remainder(min(amount, total), weights, total)
    end
  end

  @spec split_unit_price(non_neg_integer(), pos_integer()) :: [{non_neg_integer(), pos_integer()}]
  def split_unit_price(total, quantity) do
    unit = div(total, quantity)
    extra = rem(total, quantity)

    Enum.reject([{unit + 1, extra}, {unit, quantity - extra}], fn {_price, count} ->
      count == 0
    end)
  end

  defp largest_remainder(amount, weights, total) do
    shares = Enum.map(weights, &div(amount * &1, total))

    bumped =
      weights
      |> Enum.with_index()
      |> Enum.sort_by(fn {weight, index} -> {-rem(amount * weight, total), index} end)
      |> Enum.take(amount - Enum.sum(shares))
      |> MapSet.new(&elem(&1, 1))

    shares
    |> Enum.with_index()
    |> Enum.map(fn {share, index} ->
      if MapSet.member?(bumped, index), do: share + 1, else: share
    end)
  end
end
