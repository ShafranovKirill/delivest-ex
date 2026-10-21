defmodule Delivest.Promo.DslTest do
  use ExUnit.Case, async: true

  alias Delivest.Promo.{Dsl, Strategy}
  alias Delivest.Promo.Dsl.Error

  test "parses conditions with precedence and several effects" do
    rules = """
    # lunch combo
    when subtotal >= 1500 and (has "pizza" x2 or fulfillment in (delivery, pickup))
    then discount 10% max 500, gift "cola" price "margarita" 399
    """

    assert {:ok, %Strategy{} = strategy} = Dsl.parse(rules)

    assert strategy.condition ==
             {:and, {:subtotal, :>=, 1500},
              {:or, {:has, "pizza", 2}, {:fulfillment, [:delivery, :pickup]}}}

    assert strategy.effects == [
             {:percent, 10, :cart, 500},
             {:gift, "cola", 1},
             {:price, "margarita", 399}
           ]

    assert Strategy.slugs(strategy) == ["pizza", "cola", "margarita"]
  end

  test "parses an unconditional product discount" do
    assert {:ok, strategy} = Dsl.parse(~s[then discount 50 rub on ("a", "b")])
    assert Strategy.unconditional?(strategy)
    assert strategy.effects == [{:amount, 50, {:products, ["a", "b"]}}]
  end

  test "parses time windows and weekdays" do
    assert {:ok, %Strategy{condition: condition}} =
             Dsl.parse("when time 22:00..02:00 and weekday in (sat, sun) then discount 5%")

    assert condition == {:and, {:time, ~T[22:00:00], ~T[02:00:00]}, {:weekday, [6, 7]}}
  end

  test "reports syntax errors with location" do
    assert {:error, [%Error{line: 2, column: 1, message: message}]} =
             Dsl.parse("when subtotal >= 10\nwhen")

    assert message =~ "when"
  end

  test "reports unexpected end and empty rules" do
    assert {:error, [%Error{message: "Unexpected end of rules"}]} =
             Dsl.parse("when has \"a\" then")

    assert {:error, [%Error{line: nil}]} = Dsl.parse("   # nothing")
    assert {:error, [%Error{}]} = Dsl.parse(nil)
  end

  test "reports unknown symbols" do
    assert {:error, [%Error{line: 1, column: 17}]} = Dsl.parse("then discount 10$")
  end

  test "collects every semantic error" do
    rules = "when fulfillment in (courier) and time 25:00..10:00 then discount 0% gift \"a\" x0"

    assert {:error, errors} = Dsl.parse(rules)
    assert length(errors) == 4
    assert Enum.all?(errors, &(&1.line == 1))
  end

  test "rejects a cap on a product discount and an empty time window" do
    assert {:error, [%Error{}]} = Dsl.parse(~s(then discount 10% on "a" max 100))
    assert {:error, [%Error{}]} = Dsl.parse("when time 10:00..10:00 then discount 5%")
  end
end
