defmodule DelivestWeb.Staff.PromotionLive.RulesBuilderTest do
  use ExUnit.Case, async: true

  alias DelivestWeb.Staff.PromotionLive.RulesBuilder

  test "round-trips constructor rules" do
    rules =
      "when subtotal >= 1500\n  and has \"pizza\" x2\n  and time 11:00..16:00\n  and weekday in (mon, fri)\n" <>
        "then discount 10% max 500,\n     discount 50 rub on (\"cola\", \"juice\"),\n     gift \"cola\" x1,\n     price \"pizza\" 399"

    assert {:ok, builder} = RulesBuilder.from_rules(rules)
    assert RulesBuilder.errors(builder) == %{}
    assert RulesBuilder.to_rules(builder) == rules
  end

  test "joins conditions with or" do
    assert {:ok, %{match: "any"} = builder} =
             RulesBuilder.from_rules(
               "when quantity > 3 or fulfillment in (pickup) then discount 5%"
             )

    assert RulesBuilder.to_rules(builder) ==
             "when quantity > 3\n  or fulfillment in (pickup)\nthen discount 5%"
  end

  test "rejects mixed and negated conditions" do
    assert :error = RulesBuilder.from_rules("when not subtotal < 1 then discount 5%")

    assert :error =
             RulesBuilder.from_rules(
               "when (quantity > 1 or subtotal > 1) and time 10:00..12:00 then discount 5%"
             )
  end

  test "reads form params and adds products" do
    builder =
      RulesBuilder.from_params(%{
        "match" => "all",
        "effects" => %{
          "0" => %{
            "type" => "percent",
            "value" => " 20 ",
            "target" => "products",
            "products" => ["", "cola"],
            "add" => "juice",
            "cap" => ""
          }
        }
      })

    assert RulesBuilder.to_rules(builder) == ~s|then discount 20% on ("cola", "juice")|
  end

  test "reports incomplete rows and skips them" do
    builder =
      RulesBuilder.new()
      |> RulesBuilder.add_condition("weekday")
      |> RulesBuilder.add_effect("amount")

    assert %{{:condition, 0} => _, {:effect, 0} => _, {:effect, 1} => _} =
             RulesBuilder.errors(builder)

    assert RulesBuilder.to_rules(builder) == ""
  end
end
