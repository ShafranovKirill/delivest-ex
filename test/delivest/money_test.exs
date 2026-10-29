defmodule Delivest.MoneyTest do
  use ExUnit.Case, async: true

  alias Delivest.Money

  test "distributes proportionally and keeps the exact sum" do
    shares = Money.distribute(100, [300, 300, 300])
    assert Enum.sum(shares) == 100
    assert Enum.sort(shares) == [33, 33, 34]
  end

  test "never exceeds a line total" do
    assert Money.distribute(1_000, [100, 50]) == [100, 50]
  end

  test "handles empty weights" do
    assert Money.distribute(10, [0, 0]) == [0, 0]
    assert Money.distribute(10, []) == []
  end

  test "splits a line total into integer unit prices" do
    assert Money.split_unit_price(250, 3) == [{84, 1}, {83, 2}]
    assert Money.split_unit_price(300, 3) == [{100, 3}]
    assert Money.split_unit_price(0, 2) == [{0, 2}]
  end

  test "formats kopecks without zero kopecks" do
    assert Money.format(59_000) == "590 ₽"
    assert Money.format(59_990) == "599,90 ₽"
    assert Money.format(150_000_05) == "150 000,05 ₽"
    assert Money.format(-1050) == "-10,50 ₽"
    assert Money.format(nil) == "0 ₽"
    assert Money.format(1234.6) == "12,35 ₽"
  end

  test "renders and parses admin input" do
    assert Money.input(150_000) == "1500"
    assert Money.input(59_990) == "599,90"
    assert Money.input("599,9") == "599,9"

    assert Money.parse("599,90") == {:ok, 59_990}
    assert Money.parse("599.9") == {:ok, 59_990}
    assert Money.parse(" 1 500 ₽ ") == {:ok, 150_000}
    assert Money.parse("590") == {:ok, 59_000}
    assert Money.parse("1,234") == :error
    assert Money.parse("abc") == :error
    assert Money.parse("") == :error
  end

  test "converts rubles of external systems" do
    assert Money.from_rubles(589.5) == 58_950
    assert Money.from_rubles(199.99) == 19_999
    assert Money.from_rubles(Decimal.new("10.005")) == 1001
    assert Money.to_rubles(59_000) == 590
    assert Money.to_rubles(58_950) == 589.5
  end

  test "percent rounds to a kopeck" do
    assert Money.percent(105, 10) == 11
    assert Money.percent(104, 10) == 10
    assert Money.percent(59_990, 15) == 8999
  end

  test "rounds up to a step" do
    assert Money.round_up(36_685, 100) == 36_700
    assert Money.round_up(36_700, 500) == 37_000
    assert Money.round_up(36_700, 100) == 36_700
  end
end
