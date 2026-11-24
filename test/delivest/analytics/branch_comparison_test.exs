defmodule Delivest.Analytics.BranchComparisonTest do
  use ExUnit.Case, async: true

  alias Delivest.Analytics.BranchComparison

  test "sorting, inclusive calendar days and undefined average check" do
    rows = [
      %{branch_id: "a", name: "A", counts: %{"revenue" => -100, "completed" => 0}},
      %{branch_id: "b", name: "B", counts: %{"revenue" => 4200, "completed" => 42}},
      %{branch_id: "c", name: "C", counts: %{"revenue" => 100, "completed" => 1}}
    ]

    period = {~D[2026-11-01], ~D[2026-11-14]}
    assert [b, c, a] = BranchComparison.rows(rows, period, "orders_per_day")
    assert {b.value, b.calendar_days, c.value, a.value} == {3.0, 14, 1 / 14, 0.0}
    assert [b, c, a] = BranchComparison.rows(rows, period, "avg_check")
    assert {b.value, c.value, a.value} == {100, 100, nil}
    assert Enum.map(BranchComparison.rows(rows, period, "revenue"), & &1.branch_id) == ~w(b c a)
  end
end
