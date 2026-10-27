defmodule Delivest.Delivery.ConditionsTest do
  use ExUnit.Case, async: true

  alias Delivest.Delivery.{Conditions, Threshold}

  defp round_trip(params) do
    params
    |> Conditions.to_thresholds()
    |> Enum.map(&struct(Threshold, order_from: &1["order_from"], price: &1["price"]))
    |> Conditions.from_thresholds()
  end

  test "the three fields turn into thresholds and back" do
    assert Conditions.to_thresholds(%{"price" => "", "min_order" => ""}) == [
             %{"order_from" => 0, "price" => 0}
           ]

    assert Conditions.to_thresholds(%{
             "min_order" => "500",
             "price" => "200",
             "free_from" => "1500"
           }) ==
             [%{"order_from" => 500, "price" => 200}, %{"order_from" => 1500, "price" => 0}]

    assert Conditions.to_thresholds(%{"price" => "0", "free_from" => "1500"}) == [
             %{"order_from" => 0, "price" => 0}
           ]

    assert round_trip(%{"min_order" => "500", "price" => "200", "free_from" => "1500"}) ==
             %{"min_order" => 500, "price" => 200, "free_from" => 1500}

    assert round_trip(%{"price" => "150"}) ==
             %{"min_order" => nil, "price" => 150, "free_from" => nil}
  end
end
