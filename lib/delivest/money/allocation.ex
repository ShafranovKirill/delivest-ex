defmodule Delivest.Money.Allocation do
  def fit(lines, target) do
    total = Enum.sum(Enum.map(lines, &(&1.price * &1.quantity)))

    if total == target or total == 0 or target < 0 or lines == [],
      do: lines,
      else: lines |> amounts(total, target) |> Enum.flat_map(&split/1)
  end

  defp amounts(lines, total, target) do
    scaled = Enum.map(lines, &{&1, div(&1.price * &1.quantity * target, total)})
    rest = target - Enum.sum(Enum.map(scaled, &elem(&1, 1)))
    List.update_at(scaled, -1, fn {line, amount} -> {line, amount + rest} end)
  end

  defp split({line, amount}) do
    unit = div(amount, line.quantity)

    case amount - unit * line.quantity do
      0 ->
        [%{line | price: unit}]

      odd ->
        [
          %{line | price: unit, quantity: line.quantity - odd},
          %{line | price: unit + 1, quantity: odd}
        ]
    end
  end
end
