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
  end
end
