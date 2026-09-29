defmodule DelivestWeb.Staff.BranchLive.BranchSelectTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  describe "branch selection page" do
    test "renders available branches for a staff member", %{conn: conn} do
      branch = insert(:branch, name: "North Branch")
      staff = insert(:staff)
      insert(:staff_branch, staff: staff, branch: branch)

      conn = init_test_session(conn, %{"staff_id" => staff.id})

      {:ok, _lv, html} = live(conn, ~p"/staff/branches/select")

      assert html =~ "Select a branch"
      assert html =~ "North Branch"
      assert html =~ "Click to activate this branch"
    end

    test "shows empty state when staff has no branches", %{conn: conn} do
      staff = insert(:staff)
      conn = init_test_session(conn, %{"staff_id" => staff.id})

      {:ok, _lv, html} = live(conn, ~p"/staff/branches/select")

      assert html =~ "You do not have access to any active branches"
    end
  end
end
