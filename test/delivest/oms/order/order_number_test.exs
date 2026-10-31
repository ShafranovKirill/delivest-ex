defmodule Delivest.Oms.Order.OrderNumberTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Oms.Order.OrderNumber

  @noon ~U[2026-10-29 09:00:00Z]

  setup do
    %{branch: insert(:branch, code: "MSK1"), other: insert(:branch, code: "SPB")}
  end

  test "counts orders of a branch within its business day", %{branch: branch} do
    assert {:ok, %{daily_number: 1, number: "261029-MSK1-001", business_date: ~D[2026-10-29]}} =
             OrderNumber.next(Repo, branch.id, @noon)

    assert {:ok, %{daily_number: 2, number: "261029-MSK1-002"}} =
             OrderNumber.next(Repo, branch.id, @noon)
  end

  test "each branch has its own counter", %{branch: branch, other: other} do
    assert {:ok, %{daily_number: 1}} = OrderNumber.next(Repo, branch.id, @noon)

    assert {:ok, %{daily_number: 1, number: "261029-SPB-001"}} =
             OrderNumber.next(Repo, other.id, @noon)
  end

  test "a new day starts at five in the morning", %{branch: branch} do
    assert {:ok, %{daily_number: 1}} = OrderNumber.next(Repo, branch.id, @noon)

    assert {:ok, %{daily_number: 2, business_date: ~D[2026-10-29]}} =
             OrderNumber.next(Repo, branch.id, ~U[2026-10-30 01:59:00Z])

    assert {:ok, %{daily_number: 1, number: "261030-MSK1-001"}} =
             OrderNumber.next(Repo, branch.id, ~U[2026-10-30 02:00:00Z])
  end

  test "numbers past a thousand keep growing", %{branch: branch} do
    Repo.query!(
      "INSERT INTO order_counters (branch_id, business_date, value) VALUES ($1, $2, 999)",
      [Ecto.UUID.dump!(branch.id), ~D[2026-10-29]]
    )

    assert {:ok, %{daily_number: 1000, number: "261029-MSK1-1000"}} =
             OrderNumber.next(Repo, branch.id, @noon)
  end
end
