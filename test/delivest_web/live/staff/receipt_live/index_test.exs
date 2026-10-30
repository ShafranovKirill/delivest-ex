defmodule DelivestWeb.Staff.ReceiptLive.IndexTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Fiscal.Receipt
  alias Delivest.Repo

  setup %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["orders.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    order = order_fixture(branch.id)
    %{conn: init_test_session(conn, %{"staff_id" => staff.id}), branch: branch, order: order}
  end

  defp receipt(order, status) do
    Repo.insert!(%Receipt{
      order_id: order.id,
      branch_id: order.branch_id,
      kind: :sell,
      provider: "atol",
      amount: 15_000,
      status: status,
      error: "32: bad"
    })
  end

  test "failed receipts are listed and raise the alert on the orders page", %{
    conn: conn,
    branch: branch,
    order: order
  } do
    failed = receipt(order, :fail)

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/receipts?status=problem")
    assert lv |> element("#receipt-row-#{failed.id}") |> render() =~ "32: bad"

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/receipts?status=done")
    refute has_element?(lv, "#receipt-row-#{failed.id}")

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/orders")
    assert has_element?(lv, "#receipt-alerts")
  end
end
