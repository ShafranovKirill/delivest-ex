defmodule DelivestWeb.Staff.ClientLive.ShowTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory
  import Delivest.OrderFixtures

  setup %{conn: conn} do
    branch = insert(:branch, name: "Main")
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    insert(:staff_branch, staff: staff, branch: branch)

    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
    %{conn: conn, branch: branch}
  end

  test "client card shows totals and the order history", %{conn: conn, branch: branch} do
    order =
      order_fixture(branch.id,
        price: 25_000,
        quantity: 2,
        attrs: %{"customer_phone" => "+79991112233", "customer_name" => "Анна"}
      )

    {:ok, lv, html} = live(conn, ~p"/staff/clients/#{order.client_id}")

    assert html =~ "Анна"
    assert html =~ "+79991112233"
    assert html =~ "500 ₽"
    assert has_element?(lv, "#client-order-#{order.id}")

    html = lv |> element("#client-order-#{order.id} button") |> render_click()
    assert html =~ "Edit Order"
  end

  test "orders list links to the client card", %{conn: conn, branch: branch} do
    order = order_fixture(branch.id, attrs: %{"customer_phone" => "+79991112244"})

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/orders")
    assert has_element?(lv, ~s{a[href="/staff/clients/#{order.client_id}"]})
  end

  test "unknown client redirects back to the list", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/staff/clients"}}} =
             live(conn, ~p"/staff/clients/#{Ecto.UUID.generate()}")
  end
end
