defmodule DelivestWeb.Staff.StaffShellTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  test "sidebar owns branch, profile and search controls", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/dashboard")
    assert has_element?(lv, "#main-sidebar #sidebar-toggle[aria-controls='main-sidebar']")
    assert has_element?(lv, "#main-sidebar #header-branch")
    assert has_element?(lv, "details#header-branch > summary[aria-controls='header-branch-menu']")
    assert has_element?(lv, "#header-branch-menu[phx-hook]")

    assert has_element?(
             lv,
             "#sidebar-branch-settings[href='/staff/branches/#{branch.slug}/edit']"
           )

    assert has_element?(lv, "#main-sidebar #command-palette-trigger")
    assert has_element?(lv, "#staff-profile-trigger[aria-expanded='false']")
    assert has_element?(lv, "#staff-profile-menu[hidden] #orders-sound-toggle")
    assert has_element?(lv, "#staff-profile-menu #header-push-toggle")
    assert has_element?(lv, "#staff-profile-menu a[href='/staff/auth/log_out']")
    assert has_element?(lv, "#staff-profile-menu #app-version")
    refute has_element?(lv, "#staff-header #command-palette-trigger")
    refute has_element?(lv, "#staff-header #header-branch")
  end

  test "limited staff keeps profile controls without order sound or identity settings", %{
    conn: conn
  } do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["products.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id})

    {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/products")
    refute has_element?(lv, "#sidebar-branch-settings")
    refute has_element?(lv, "#staff-profile-menu #orders-sound-toggle")
    assert has_element?(lv, "#staff-profile-menu #header-push-toggle")
  end

  test "page title is portaled while body actions stay in the page", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id})

    {:ok, lv, _} = live(conn, ~p"/staff/branches")
    assert has_element?(lv, "#staff-header-title")
    assert render(element(lv, "#staff-page-header")) =~ "Settings for branches"
    assert has_element?(lv, "#branch-settings-list #create-branch")
    refute has_element?(lv, "#branch-settings-list h1")
  end
end
