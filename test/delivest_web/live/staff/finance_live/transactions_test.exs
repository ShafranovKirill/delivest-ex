defmodule DelivestWeb.Staff.FinanceLive.TransactionsTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Payments
  alias Delivest.Payments.Payment
  alias Delivest.Repo

  setup %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["finance.read", "orders.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    order = order_fixture(branch.id)
    %{conn: init_test_session(conn, %{"staff_id" => staff.id}), branch: branch, order: order}
  end

  defp payment(order, status, inserted_at \\ DateTime.utc_now() |> DateTime.truncate(:second)) do
    Repo.insert!(%Payment{
      order_id: order.id,
      branch_id: order.branch_id,
      method: :cash,
      amount: 15_000,
      status: status,
      inserted_at: inserted_at
    })
  end

  test "register links payment to its order and keeps payment settings reachable", %{
    conn: conn,
    branch: branch,
    order: order
  } do
    row = payment(order, :pending)
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/finance/transactions")

    assert has_element?(
             lv,
             "#payment-row-#{row.id} a[href='/staff/b/#{branch.slug}/orders/#{order.id}']"
           )

    assert has_element?(
             lv,
             "#staff-page-header a[href='/staff/b/#{branch.slug}/finance/payments']"
           )

    assert has_element?(lv, "#transactions-page-size option[value='25'][selected]")
  end

  test "status, order search and local day filter the register without crossing branches", %{
    conn: conn,
    branch: branch,
    order: order
  } do
    selected = payment(order, :paid, ~U[2026-01-10 21:30:00Z])
    other_order = order_fixture(branch.id)
    payment(other_order, :paid, ~U[2026-01-11 21:30:00Z])
    payment(order_fixture(insert(:branch).id), :paid, ~U[2026-01-10 21:30:00Z])

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/finance/transactions")

    lv
    |> form("#transactions-filter-form", %{
      "search" => order.number,
      "status" => "paid",
      "from" => "2026-01-11",
      "to" => "2026-01-11"
    })
    |> render_submit()

    assert_patch(lv)
    assert has_element?(lv, "#payment-row-#{selected.id}")
    assert has_element?(lv, "#transactions-page")

    {rows, meta} =
      Payments.list_branch_page(branch.id, %{
        "status" => "paid",
        "search" => order.number,
        "from" => "2026-01-11",
        "to" => "2026-01-11"
      })

    assert Enum.map(rows, fn {row, _} -> row.id end) == [selected.id]
    assert meta.total == 1
  end

  test "malformed parameters cannot crash or expand the register", %{branch: branch, order: order} do
    inserted = payment(order, :pending)

    {rows, meta} =
      Payments.list_branch_page(branch.id, %{
        "page" => %{"nested" => "2"},
        "page_size" => ["100"],
        "search" => %{"nested" => "x"},
        "from" => ["2026-01-01"]
      })

    assert Enum.any?(rows, fn {row, _} -> row.id == inserted.id end)
    assert meta.total == length(rows)
    assert meta.page == 1
    assert meta.page_size == 25
  end

  test "finance reader without order access sees the operation but no order link", %{
    branch: branch,
    order: order
  } do
    row = payment(order, :pending)
    staff = insert(:staff, role: insert(:role, permissions: ["finance.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = Phoenix.ConnTest.build_conn() |> init_test_session(%{"staff_id" => staff.id})

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/finance/transactions")
    assert has_element?(lv, "#payment-row-#{row.id}")
    refute has_element?(lv, "#payment-row-#{row.id} a[href*='/orders/']")
  end
end
