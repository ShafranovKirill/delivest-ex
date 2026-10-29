defmodule Delivest.Delivery.Conditions do
  alias Delivest.Delivery.Threshold
  alias Delivest.Money

  def from_thresholds([]), do: %{"min_order" => nil, "price" => nil, "free_from" => nil}

  def from_thresholds(thresholds) do
    [first | rest] = Threshold.sort(thresholds)
    free = Enum.find(rest, &(&1.price == 0))

    %{
      "min_order" => if(first.order_from > 0, do: first.order_from),
      "price" => first.price,
      "free_from" => free && free.order_from
    }
  end

  def to_thresholds(params) do
    min_order = number(params["min_order"]) || 0
    price = number(params["price"]) || 0
    free_from = number(params["free_from"])

    first = %{"order_from" => min_order, "price" => price}

    if free_from && price > 0 && free_from > min_order,
      do: [first, %{"order_from" => free_from, "price" => 0}],
      else: [first]
  end

  defp number(value) when is_integer(value) and value >= 0, do: value

  defp number(value) when is_binary(value) do
    case Money.parse(value) do
      {:ok, amount} when amount >= 0 -> amount
      _ -> nil
    end
  end

  defp number(_value), do: nil
end
