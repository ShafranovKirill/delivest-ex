defmodule DelivestWeb.Staff.BranchLive.BranchesTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  describe "branches management page" do
    test "renders the branches page for an admin staff member", %{conn: conn} do
      branch = insert(:branch, name: "Main Branch")
      admin_role = insert(:role, permissions: ["admin"])
      staff = insert(:staff, role: admin_role)

      conn = init_test_session(conn, %{"staff_id" => staff.id})

      {:ok, _lv, html} = live(conn, ~p"/staff/branches")

      assert html =~ "Branches Management"
      assert html =~ "Create Branch"
      assert html =~ branch.name
    end
  end
end
