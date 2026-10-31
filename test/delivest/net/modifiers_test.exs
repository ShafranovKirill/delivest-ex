defmodule Delivest.Net.ModifiersTest do
  use ExUnit.Case, async: true

  alias Delivest.Net.{Modifier, ModifierGroup, Modifiers}

  @small %Modifier{id: "small", name: "25 см", price: 0, is_default: true}
  @large %Modifier{id: "large", name: "35 см", price: 20_000}
  @cheese %Modifier{id: "cheese", name: "Сыр", price: 5_000, max_quantity: 2}
  @bacon %Modifier{id: "bacon", name: "Бекон", price: 7_000}

  @size %ModifierGroup{name: "Размер", min: 1, max: 1, modifiers: [@small, @large]}
  @extras %ModifierGroup{name: "Добавки", min: 0, max: 2, modifiers: [@cheese, @bacon]}
  @groups [@size, @extras]

  test "no choice takes the defaults" do
    assert {:ok, [%{id: "small", quantity: 1}]} = Modifiers.resolve(@groups, nil)
  end

  test "a required group falls back to its default when only extras are chosen" do
    assert {:ok, choices} = Modifiers.resolve(@groups, [%{"id" => "cheese", "quantity" => 2}])
    assert Enum.map(choices, &{&1.id, &1.quantity}) == [{"small", 1}, {"cheese", 2}]
    assert Modifiers.price(choices) == 10_000
  end

  test "limits, quantities and stops are checked" do
    assert {:error, :modifiers_limit} =
             Modifiers.resolve(@groups, ["large", "cheese", "cheese", "bacon"])

    assert {:error, :modifier_quantity} =
             Modifiers.resolve(@groups, [%{"id" => "bacon", "quantity" => 2}])

    assert {:error, :modifier_unavailable} = Modifiers.resolve(@groups, ["ham"])

    assert {:error, :modifier_unavailable} =
             Modifiers.resolve(@groups, ["bacon"], MapSet.new(["bacon"]))

    no_default = %{@size | modifiers: [%{@small | is_default: false}, @large]}
    assert {:error, :modifiers_required} = Modifiers.resolve([no_default], nil)
  end

  test "the key does not depend on the order of choices" do
    {:ok, one} = Modifiers.resolve(@groups, ["large", "bacon", "cheese"])
    {:ok, two} = Modifiers.resolve(@groups, ["cheese", "large", "bacon"])
    assert Modifiers.key(one) == Modifiers.key(two)
  end
end
