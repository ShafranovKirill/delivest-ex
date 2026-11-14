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

  test "modal chooser keeps the target until the selected branch is explicit", %{conn: conn} do
    first = insert(:branch, name: "First")
    second = insert(:branch, name: "Second")
    denied = insert(:branch, name: "Denied")
    staff = insert(:staff, role: insert(:role, permissions: ["products.read"]))
    insert(:staff_branch, staff: staff, branch: first)
    insert(:staff_branch, staff: staff, branch: second)
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => first.id})
    target = "/staff/b/#{first.slug}/products"
    chooser = DelivestWeb.StaffBranchPath.selection_path(target, "/staff/dashboard")

    for _ <- 1..2 do
      {:ok, view, _} = live(conn, chooser)

      assert has_element?(
               view,
               "#branch-select-dialog[role='dialog'][aria-modal='true'][data-close-event='close_branch_selector']"
             )

      assert has_element?(
               view,
               "#branch-select-dialog a[href^='/staff/branches/select/#{first.id}?'][href*='from=']"
             )

      assert has_element?(
               view,
               "#branch-select-dialog a[href^='/staff/branches/select/#{second.id}?'][href*='from=']"
             )

      refute has_element?(view, "#branch-select-dialog a[href*='#{denied.id}']")
      assert has_element?(view, "#branch-select-dialog button[phx-click='close_branch_selector']")
    end

    {:ok, view, _} = live(conn, chooser)
    render_click(view, "close_branch_selector", %{})
    assert_redirect(view, "/staff/dashboard")

    selected =
      get(conn, "/staff/branches/select/#{second.id}?" <> URI.encode_query(%{"from" => target}))

    assert redirected_to(selected) == "/staff/b/#{second.slug}/products"
    assert get_session(selected, :active_branch_id) == second.id
  end

  test "modal chooser rejects an external source and keeps cancel local", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff)
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id})

    {:ok, invalid, _} =
      live(conn, "/staff/branches/select?modal=true&from=https%3A%2F%2Fevil.example")

    refute has_element?(invalid, "#branch-select-dialog")

    chooser =
      DelivestWeb.StaffBranchPath.selection_path(
        "/staff/b/#{branch.slug}/products",
        "https://evil.example"
      )

    {:ok, view, _} = live(conn, chooser)
    assert has_element?(view, "#branch-select-dialog")
    render_click(view, "close_branch_selector", %{})
    assert_redirect(view, "/staff/dashboard")
  end

  test "modal chooser shows an empty state when no branches are accessible", %{conn: conn} do
    staff = insert(:staff)
    conn = init_test_session(conn, %{"staff_id" => staff.id})

    chooser =
      DelivestWeb.StaffBranchPath.selection_path(
        "/staff/b/placeholder/products",
        "/staff/dashboard"
      )

    {:ok, view, _} = live(conn, chooser)

    assert has_element?(
             view,
             "#branch-select-dialog",
             "You do not have access to any active branches"
           )

    refute has_element?(view, "#branch-select-dialog a[href^='/staff/branches/select/']")
  end
end
