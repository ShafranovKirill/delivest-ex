defmodule Delivest.Promo.Basket do
  alias Delivest.Promo.Line

  @type t :: %__MODULE__{lines: [Line.t()], discounts: %{binary() => non_neg_integer()}}

  defstruct lines: [], discounts: %{}

  def new(items), do: %__MODULE__{lines: Enum.map(items, &Line.paid/1)}

  def paid(%__MODULE__{lines: lines}), do: Enum.reject(lines, & &1.gift)

  def gifts(%__MODULE__{lines: lines}), do: Enum.filter(lines, & &1.gift)

  def subtotal(basket), do: basket |> paid() |> Enum.map(&Line.base_total/1) |> Enum.sum()

  def total(basket), do: basket |> paid() |> Enum.map(& &1.total) |> Enum.sum()

  def quantity(basket), do: basket |> paid() |> Enum.map(& &1.quantity) |> Enum.sum()

  def quantities(basket) do
    basket
    |> paid()
    |> Enum.reduce(%{}, fn line, acc ->
      Map.update(acc, line.product_id, line.quantity, &(&1 + line.quantity))
    end)
  end

  def update_paid(%__MODULE__{} = basket, fun) do
    %{basket | lines: Enum.map(basket.lines, &if(&1.gift, do: &1, else: fun.(&1)))}
  end

  def add_lines(%__MODULE__{} = basket, lines), do: %{basket | lines: basket.lines ++ lines}

  def credit(%__MODULE__{} = basket, _promotion_id, 0), do: basket

  def credit(%__MODULE__{} = basket, promotion_id, amount),
    do: %{basket | discounts: Map.update(basket.discounts, promotion_id, amount, &(&1 + amount))}

  def discount_for(%__MODULE__{discounts: discounts}, promotion_id),
    do: Map.get(discounts, promotion_id, 0)
end
