defmodule Delivest.Money.AllocationTest do
  use ExUnit.Case, async: true

  alias Delivest.Money.Allocation

  defp total(lines), do: Enum.sum(Enum.map(lines, &(&1.price * &1.quantity)))

  test "lines that already match stay as they are" do
    lines = [%{price: 500, quantity: 2}]
    assert Allocation.fit(lines, 1000) == lines
  end

  test "a discount spreads over lines and splits uneven quantities" do
    lines = [%{price: 1000, quantity: 3}, %{price: 500, quantity: 1}]
    fitted = Allocation.fit(lines, 3001)

    assert total(fitted) == 3001
    assert Enum.all?(fitted, &(&1.quantity > 0))
    assert [%{quantity: 2}, %{quantity: 1}, %{quantity: 1}] = fitted
  end

  test "zero lines keep their zero price" do
    fitted = Allocation.fit([%{price: 0, quantity: 1}, %{price: 900, quantity: 1}], 800)
    assert [%{price: 0}, %{price: 800}] = fitted
  end
end
