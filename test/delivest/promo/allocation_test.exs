defmodule Delivest.Promo.AllocationTest do
  use ExUnit.Case, async: true

  alias Delivest.Promo.Allocation

  test "distributes proportionally and keeps the exact sum" do
    shares = Allocation.distribute(100, [300, 300, 300])
    assert Enum.sum(shares) == 100
    assert Enum.sort(shares) == [33, 33, 34]
  end

  test "never exceeds a line total" do
    assert Allocation.distribute(1_000, [100, 50]) == [100, 50]
  end

  test "handles empty weights" do
    assert Allocation.distribute(10, [0, 0]) == [0, 0]
    assert Allocation.distribute(10, []) == []
  end

  test "splits a line total into integer unit prices" do
    assert Allocation.split_unit_price(250, 3) == [{84, 1}, {83, 2}]
    assert Allocation.split_unit_price(300, 3) == [{100, 3}]
    assert Allocation.split_unit_price(0, 2) == [{0, 2}]
  end
end
