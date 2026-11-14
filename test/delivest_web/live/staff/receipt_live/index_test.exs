defmodule DelivestWeb.Staff.ReceiptLive.IndexTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Fiscal.Receipt
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Crm.BranchSettings
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

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/finance/receipts?status=problem")
    assert lv |> element("#receipt-row-#{failed.id}") |> render() =~ "32: bad"

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/finance/receipts?status=done")
    refute has_element?(lv, "#receipt-row-#{failed.id}")

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/orders")
    assert has_element?(lv, "#receipt-alerts")
  end

  test "order search and branch-local dates preserve the receipt list URL", %{
    conn: conn,
    branch: branch,
    order: order
  } do
    listed = receipt(order, :done)
    other_order = order_fixture(branch.id)
    other = receipt(other_order, :done)

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/finance/receipts")
    assert has_element?(lv, "#receipt-row-#{listed.id}")
    assert has_element?(lv, "#receipt-row-#{other.id}")

    lv
    |> form("#receipts-filter-form", %{
      "search" => order.number,
      "from" => Date.utc_today() |> Date.add(-1) |> Date.to_iso8601(),
      "to" => Date.utc_today() |> Date.add(1) |> Date.to_iso8601()
    })
    |> render_submit()

    assert_patch(lv)
    assert has_element?(lv, "#receipt-row-#{listed.id}")
    refute has_element?(lv, "#receipt-row-#{other.id}")
    assert has_element?(lv, "#receipts-page-size option[value='25'][selected]")
  end

  test "existing receipt remains visible after CRM takes ownership", %{conn: conn} do
    branch = insert(:branch)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{enabled: true, provider: :iiko}
    })

    staff = insert(:staff, role: insert(:role, permissions: ["orders.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    pending = branch.id |> order_fixture() |> receipt(:wait)
    conn = init_test_session(conn, %{"staff_id" => staff.id})

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/finance/receipts")
    assert has_element?(lv, "#receipt-row-#{pending.id}")
    assert has_element?(lv, "#receipts-external-owner[role='status']")
    refute has_element?(lv, "#gateway-owner-screen")
  end
end
