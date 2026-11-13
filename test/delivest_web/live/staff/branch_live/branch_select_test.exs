defmodule DelivestWeb.Staff.BranchLive.BranchSelectTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Repo

  describe "branch selection page" do
    test "renders available branches for a staff member", %{conn: conn} do
      branch = insert(:branch, name: "North Branch")
      staff = insert(:staff)
      insert(:staff_branch, staff: staff, branch: branch)

      conn = init_test_session(conn, %{"staff_id" => staff.id})

      {:ok, lv, html} = live(conn, ~p"/staff/branches/select")

      assert html =~ "Select a branch"
      assert has_element?(lv, "main #staff-page-header h1", "Select a branch")
      assert render(element(lv, "#staff-page-header")) =~ "Select a branch"
      assert html =~ "North Branch"
      assert html =~ "Click to activate this branch"
    end

    test "shows empty state when staff has no branches", %{conn: conn} do
      staff = insert(:staff)
      conn = init_test_session(conn, %{"staff_id" => staff.id})

      {:ok, _lv, html} = live(conn, ~p"/staff/branches/select")

      assert html =~ "You do not have access to any active branches"
    end

    test "kitchen staff sees only branches with a working kitchen", %{conn: conn} do
      staff = insert(:staff, role: build(:role, permissions: ["orders.cook"]))
      working = insert(:branch, name: "Working Kitchen")
      off = insert(:branch, name: "Off Kitchen")

      insert(:staff_branch, staff: staff, branch: working)
      insert(:staff_branch, staff: staff, branch: off)

      Repo.insert!(%BranchInfo{branch_id: working.id, kitchen: %{enabled: true}})
      Repo.insert!(%BranchInfo{branch_id: off.id, kitchen: %{enabled: false}})

      conn = init_test_session(conn, %{"staff_id" => staff.id})
      {:ok, lv, _html} = live(conn, ~p"/staff/branches/select")

      assert has_element?(lv, "#branch-select-kitchen-note")
      assert has_element?(lv, ~s|a[href="/staff/branches/select/#{working.id}"]|)
      refute has_element?(lv, ~s|a[href="/staff/branches/select/#{off.id}"]|)

      assert has_element?(
               lv,
               "#branch-select-disabled-#{off.id}",
               "The kitchen is off in the branch settings"
             )
    end

    test "kitchen staff without a working branch can log out", %{conn: conn} do
      staff = insert(:staff, role: build(:role, permissions: ["orders.cook"]))
      branch = insert(:branch, name: "Off Kitchen")

      insert(:staff_branch, staff: staff, branch: branch)
      Repo.insert!(%BranchInfo{branch_id: branch.id, kitchen: %{enabled: false}})

      conn = init_test_session(conn, %{"staff_id" => staff.id})
      {:ok, lv, _html} = live(conn, ~p"/staff/branches/select")

      assert has_element?(lv, "#branch-select-no-kitchen")
      assert has_element?(lv, ~s|#branch-select-no-kitchen a[href="/staff/auth/log_out"]|)
    end

    test "the home page does not send kitchen staff to a disabled kitchen", %{conn: conn} do
      staff = insert(:staff, role: build(:role, permissions: ["orders.cook"]))
      branch = insert(:branch, name: "Off Kitchen")

      insert(:staff_branch, staff: staff, branch: branch)
      Repo.insert!(%BranchInfo{branch_id: branch.id, kitchen: %{enabled: false}})

      conn =
        conn
        |> init_test_session(%{"staff_id" => staff.id, "active_branch_id" => branch.id})
        |> get(~p"/staff")

      assert redirected_to(conn) == ~p"/staff/branches/select"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "The kitchen is off in the branch settings"
    end

    test "choosing a branch with a disabled kitchen explains and keeps the choice", %{conn: conn} do
      staff = insert(:staff, role: build(:role, permissions: ["orders.cook"]))
      branch = insert(:branch, name: "Off Kitchen")

      insert(:staff_branch, staff: staff, branch: branch)
      Repo.insert!(%BranchInfo{branch_id: branch.id, kitchen: %{enabled: false}})

      conn =
        conn
        |> init_test_session(%{"staff_id" => staff.id})
        |> get(~p"/staff/branches/select/#{branch.id}")

      assert redirected_to(conn) == ~p"/staff/branches/select"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "The kitchen is off in the branch settings"

      assert get_session(conn, :active_branch_id) == nil
    end
  end
end
