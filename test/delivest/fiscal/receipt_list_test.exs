defmodule Delivest.Fiscal.ReceiptListTest do
  use DelivestWeb.ConnCase, async: true

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Fiscal
  alias Delivest.Fiscal.Receipt
  alias Delivest.Repo

  defp receipt(order, status, inserted_at \\ DateTime.utc_now() |> DateTime.truncate(:second)) do
    Repo.insert!(%Receipt{
      order_id: order.id,
      branch_id: order.branch_id,
      kind: :sell,
      provider: "atol",
      amount: 15_000,
      status: status,
      inserted_at: inserted_at
    })
  end

  test "branch-local day and combined order/status filters select only the intended receipt" do
    branch = insert(:branch)
    other_branch = insert(:branch)
    first_order = order_fixture(branch.id)
    second_order = order_fixture(branch.id)
    outsider_order = order_fixture(other_branch.id)
    on_day = receipt(first_order, :done, ~U[2026-01-10 21:30:00Z])
    receipt(second_order, :done, ~U[2026-01-11 21:30:00Z])
    receipt(outsider_order, :done, ~U[2026-01-10 21:30:00Z])

    {rows, meta} =
      Fiscal.list_branch_page(branch.id, %{
        "from" => "2026-01-11",
        "to" => "2026-01-11",
        "search" => first_order.number,
        "status" => "done"
      })

    assert Enum.map(rows, fn {row, _number} -> row.id end) == [on_day.id]
    assert meta.total == 1
  end

  test "pagination is stable, branch scoped, and malformed URL values fall back safely" do
    branch = insert(:branch)
    order = order_fixture(branch.id)
    outsider = order_fixture(insert(:branch).id)
    receipts = for _ <- 1..26, do: receipt(order, :fail)
    receipt(outsider, :fail)

    {first, first_meta} = Fiscal.list_branch_page(branch.id, %{"page" => "1"})
    {second, second_meta} = Fiscal.list_branch_page(branch.id, %{"page" => "2"})

    assert length(first) == 25
    assert length(second) == 1
    assert first_meta.pages == 2
    assert second_meta.page == 2

    assert MapSet.new(Enum.map(first ++ second, fn {row, _} -> row.id end)) ==
             MapSet.new(Enum.map(receipts, & &1.id))

    {fallback, fallback_meta} =
      Fiscal.list_branch_page(branch.id, %{
        "page" => %{"nested" => "1"},
        "page_size" => ["100"],
        "search" => %{"nested" => "x"},
        "from" => ["2026-01-01"]
      })

    assert length(fallback) == 25
    assert fallback_meta.page == 1
    assert fallback_meta.page_size == 25
  end
end
