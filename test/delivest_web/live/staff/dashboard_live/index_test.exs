defmodule DelivestWeb.Staff.DashboardLive.IndexTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  describe "dashboard page" do
    test "redirects unauthenticated staff to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/staff/auth/login"}}} =
               live(conn, ~p"/staff/b/#{insert(:branch)}/dashboard")
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

      {:ok, _lv, html} = live(conn, ~p"/staff/b/#{branch}/dashboard")

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

      {:ok, lv, html} = live(conn, ~p"/staff/b/#{branch}/dashboard")

      assert html =~ "450 ₽"
      assert has_element?(lv, "#dashboard-order-#{order.id}")

      second = Delivest.OrderFixtures.order_fixture(branch.id, price: 50)
      refute has_element?(lv, "#dashboard-order-#{second.id}")

      send(lv.pid, :reload)
      assert has_element?(lv, "#dashboard-order-#{second.id}")
      assert render(lv) =~ "500 ₽"
    end
  end

  describe "header" do
    setup %{conn: conn} do
      branch = insert(:branch, name: "Main Branch")
      staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
      insert(:staff_branch, staff: staff, branch: branch)

      conn =
        init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

      %{conn: conn, branch: branch}
    end

    test "counts orders awaiting confirmation live", %{conn: conn, branch: branch} do
      Delivest.OrderFixtures.order_fixture(branch.id, price: 100)
      {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/dashboard")

      assert has_element?(lv, "#header-new-orders-count", "1")

      Delivest.OrderFixtures.order_fixture(branch.id, price: 100)
      assert has_element?(lv, "#header-new-orders-count", "2")
    end

    test "log out lives in the header, not the sidebar", %{conn: conn, branch: branch} do
      {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/dashboard")

      assert has_element?(lv, "header a[href='/staff/auth/log_out']")
      refute has_element?(lv, "#main-sidebar a[href='/staff/auth/log_out']")
      refute has_element?(lv, "#main-sidebar a[href='/staff/branches/select']")
    end

    test "theme switch lives in the user menu and new order is not in the header", %{
      conn: conn,
      branch: branch
    } do
      {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/dashboard")

      assert has_element?(lv, "header .dropdown #header-theme-dark")
      assert has_element?(lv, "header .dropdown #header-theme-light")
      refute has_element?(lv, "header a[href='/staff/orders/new']")
    end
  end
end
