defmodule DelivestWeb.Staff.DashboardLive.IndexTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  describe "dashboard page" do
    test "redirects unauthenticated staff to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/staff/auth/login"}}} =
               live(conn, ~p"/staff/dashboard")
    end

    test "renders dashboard for authenticated staff in an active branch", %{conn: conn} do
      branch = insert(:branch, name: "Main Branch")
      staff = insert(:staff)
      insert(:staff_branch, staff: staff, branch: branch)

      conn =
        init_test_session(conn, %{
          "staff_id" => staff.id,
          "active_branch_id" => branch.id
        })

      {:ok, _lv, html} = live(conn, ~p"/staff/dashboard")

      assert html =~ "Dashboard"
      assert html =~ "Log out"
    end

    test "shows today's sales and latest orders", %{conn: conn} do
      branch = insert(:branch, name: "Main Branch")
      staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
      insert(:staff_branch, staff: staff, branch: branch)
      order = Delivest.OrderFixtures.order_fixture(branch.id, price: 450)

      conn =
        init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

      {:ok, lv, html} = live(conn, ~p"/staff/dashboard")

      assert html =~ "450 ₽"
      assert has_element?(lv, "#dashboard-order-#{order.id}")

      second = Delivest.OrderFixtures.order_fixture(branch.id, price: 50)
      refute has_element?(lv, "#dashboard-order-#{second.id}")

      send(lv.pid, :reload)
      assert has_element?(lv, "#dashboard-order-#{second.id}")
      assert render(lv) =~ "500 ₽"
    end
  end
end
