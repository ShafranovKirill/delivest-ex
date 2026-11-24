defmodule DelivestWeb.Staff.BranchLive.BranchSelectTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Features
  alias Delivest.Repo

  describe "branch selection page" do
    test "renders available branches for a staff member", %{conn: conn} do
      branch = insert(:branch, name: "North Branch")
      staff = insert(:staff)
      insert(:staff_branch, staff: staff, branch: branch)

      conn = init_test_session(conn, %{"staff_id" => staff.id})

      {:ok, lv, html} = live(conn, ~p"/staff/branches/select")

      assert html =~ "Select a branch"
      assert has_element?(lv, "#branch-select-page")
      refute has_element?(lv, "#staff-context-navigation[data-branch-chooser-nav='true']")
      assert has_element?(lv, "main #staff-page-header h1", "Select a branch")
      assert render(element(lv, "#staff-page-header")) =~ "Select a branch"
      assert has_element?(lv, "#branch-select-card-#{branch.id}", "North Branch")

      assert has_element?(
               lv,
               "#branch-select-go-#{branch.id}[aria-describedby='branch-select-title-#{branch.id}']",
               "Go"
             )

      assert has_element?(lv, "#branch-select-all", "All branches")
      refute html =~ "Click to activate this branch"
    end

    test "shows empty state when staff has no branches", %{conn: conn} do
      staff = insert(:staff)
      conn = init_test_session(conn, %{"staff_id" => staff.id})

      {:ok, lv, html} = live(conn, ~p"/staff/branches/select")

      assert html =~ "You do not have access to any active branches"
      refute has_element?(lv, "#branch-select-all")
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
      refute has_element?(lv, "#branch-select-all")
      assert has_element?(lv, "#branch-select-go-#{working.id}")
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

  test "chooser keeps the target until the selected branch is explicit", %{conn: conn} do
    first = insert(:branch, name: "First")
    second = insert(:branch, name: "Second")
    denied = insert(:branch, name: "Denied")
    staff = insert(:staff, role: insert(:role, permissions: ["products.read"]))
    insert(:staff_branch, staff: staff, branch: first)
    insert(:staff_branch, staff: staff, branch: second)
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => first.id})
    target = "/staff/b/#{first.slug}/products"
    chooser = DelivestWeb.StaffBranchPath.selection_path(target, "/staff/dashboard")
    refute chooser =~ "modal="

    for _ <- 1..2 do
      {:ok, view, _} = live(conn, chooser)

      assert has_element?(view, "#branch-select-page")
      assert has_element?(view, "#staff-page-header a[href='/staff/dashboard']")
      refute has_element?(view, "#branch-select-dialog")
      refute has_element?(view, "#branch-select-all")

      assert has_element?(
               view,
               "#branch-select-go-#{first.id}[href^='/staff/branches/select/#{first.id}?'][href*='from=']"
             )

      assert has_element?(
               view,
               "#branch-select-go-#{second.id}[href^='/staff/branches/select/#{second.id}?'][href*='from=']"
             )

      refute has_element?(view, "#branch-select-go-#{denied.id}")
    end

    selected =
      get(conn, "/staff/branches/select/#{second.id}?" <> URI.encode_query(%{"from" => target}))

    assert redirected_to(selected) == "/staff/b/#{second.slug}/products"
    assert get_session(selected, :active_branch_id) == second.id
  end

  test "chooser keeps popular products active and sibling links inside selection", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id})
    source = "/staff/b/#{branch.slug}/menu/popular"
    chooser = DelivestWeb.StaffBranchPath.selection_path(source, "/staff/segments")

    {:ok, view, _} = live(conn, chooser)

    assert has_element?(view, "#staff-context-navigation[data-branch-chooser-nav='true']")

    assert has_element?(
             view,
             "#staff-section-navigation #product-section-tab-popular[aria-current='page']"
           )

    assert has_element?(
             view,
             "#staff-section-navigation #product-section-tab-products[href^='/staff/branches/select?'][href*='from=']"
           )

    assert has_element?(view, "#branch-select-go-#{branch.id}[href*='from=']")
  end

  test "chooser keeps order and settings section navigation", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id})

    for {source, selector} <- [
          {"/staff/b/#{branch.slug}/orders",
           "#staff-section-navigation #section-nav-orders[aria-current='page']"},
          {"/staff/b/#{branch.slug}/deliveries",
           "#staff-section-navigation #section-nav-deliveries[aria-current='page']"},
          {"/staff/b/#{branch.slug}/integrations",
           "#settings-navigation #settings-nav-integrations[aria-current='page']"}
        ] do
      chooser = DelivestWeb.StaffBranchPath.selection_path(source, "/staff/dashboard")
      {:ok, view, _} = live(conn, chooser)
      assert has_element?(view, "#staff-context-navigation[data-branch-chooser-nav='true']")
      assert has_element?(view, selector)
      assert has_element?(view, "#branch-select-go-#{branch.id}[href*='from=']")
    end
  end

  test "chooser navigation uses an accessible branch when the source branch is denied", %{
    conn: conn
  } do
    allowed = insert(:branch)
    denied = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["products.read"]))
    insert(:staff_branch, staff: staff, branch: allowed)
    conn = init_test_session(conn, %{"staff_id" => staff.id})
    source = "/staff/b/#{denied.slug}/products"
    chooser = DelivestWeb.StaffBranchPath.selection_path(source, "/staff/dashboard")

    {:ok, view, _} = live(conn, chooser)

    assert has_element?(view, "#staff-context-navigation[data-branch-chooser-nav='true']")

    assert has_element?(
             view,
             "#staff-section-navigation #product-section-tab-products[aria-current='page']"
           )

    assert has_element?(view, "#branch-select-go-#{allowed.id}[href*='from=']")
    refute has_element?(view, "#branch-select-card-#{denied.id}")
  end

  test "chooser rejects an external source and keeps Back local", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff)
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id})

    {:ok, invalid, _} =
      live(conn, "/staff/branches/select?modal=true&from=https%3A%2F%2Fevil.example")

    refute has_element?(invalid, "#branch-select-dialog")
    refute has_element?(invalid, "#staff-page-header a")
    assert has_element?(invalid, "#branch-select-card-#{branch.id}")

    chooser =
      DelivestWeb.StaffBranchPath.selection_path(
        "/staff/b/#{branch.slug}/products",
        "https://evil.example"
      )

    {:ok, view, _} = live(conn, chooser)
    assert has_element?(view, "#staff-page-header a[href='/staff/dashboard']")
    refute has_element?(view, "#branch-select-dialog")

    legacy = chooser <> "&modal=true"
    {:ok, old, _} = live(conn, legacy)
    assert has_element?(old, "#branch-select-go-#{branch.id}[href*='from=']")
  end

  test "chooser shows an empty state when no branches are accessible", %{conn: conn} do
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
             "#branch-select-page",
             "You do not have access to any active branches"
           )

    refute has_element?(view, "#branch-select-page a[href^='/staff/branches/select/']")
    refute has_element?(view, "#branch-select-all")
  end

  test "network card appears only for a compatible allowed scope", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["statistics.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id})
    source = "/staff/b/#{branch.slug}/statistics?period=custom&from=2026-11-01&to=2026-11-07"
    chooser = DelivestWeb.StaffBranchPath.selection_path(source, "/staff/dashboard")

    {:ok, limited, _} = live(conn, chooser)
    refute has_element?(limited, "#branch-select-all")

    network_staff =
      insert(:staff,
        role: insert(:role, permissions: ["statistics.read", "statistics.network"])
      )

    insert(:staff_branch, staff: network_staff, branch: branch)
    network_conn = init_test_session(conn, %{"staff_id" => network_staff.id})
    {:ok, allowed, _} = live(network_conn, chooser)
    assert has_element?(allowed, "#branch-select-all")
    assert has_element?(allowed, "#branch-select-all-go[href*='from=']", "Go")

    selected =
      get(network_conn, "/staff/branches/all?" <> URI.encode_query(%{"from" => source}))

    assert redirected_to(selected) ==
             "/staff/statistics?from=2026-11-01&period=custom&to=2026-11-07"
  end

  test "general chooser excludes network card for kitchen and branch creation", %{conn: conn} do
    branch = insert(:branch)
    kitchen = insert(:staff, role: build(:role, permissions: ["orders.cook"]))
    insert(:staff_branch, staff: kitchen, branch: branch)
    kitchen_conn = init_test_session(conn, %{"staff_id" => kitchen.id})
    {:ok, kitchen_view, _} = live(kitchen_conn, ~p"/staff/branches/select")
    refute has_element?(kitchen_view, "#branch-select-all")

    staff = insert(:staff, role: insert(:role, permissions: ["orders.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    staff_conn = init_test_session(conn, %{"staff_id" => staff.id})

    chooser =
      DelivestWeb.StaffBranchPath.selection_path(
        "/staff/b/#{branch.slug}/orders/new",
        "/staff/dashboard"
      )

    {:ok, create_view, _} = live(staff_conn, chooser)
    refute has_element?(create_view, "#branch-select-all")
  end

  test "network analytics chooser filters branches by report feature and keeps both destinations",
       %{
         conn: conn
       } do
    enabled = insert(:branch)
    disabled = insert(:branch)

    staff =
      insert(:staff,
        role: insert(:role, permissions: ["statistics.read", "statistics.network"])
      )

    insert(:staff_branch, staff: staff, branch: enabled)
    insert(:staff_branch, staff: staff, branch: disabled)
    assert {:ok, _} = Features.configure("analytics_links", :franchise, true, actor: "test")

    assert {:ok, _} =
             Features.configure("analytics_links", {:branch, enabled.id}, true, actor: "test")

    conn = init_test_session(conn, %{"staff_id" => staff.id})
    source = "/staff/analytics/sources?period=month"
    chooser = DelivestWeb.StaffBranchPath.selection_path(source, "/staff/dashboard")
    {:ok, view, _} = live(conn, chooser)

    assert has_element?(view, "#branch-select-all-go[href*='from=']")
    assert has_element?(view, "#branch-select-go-#{enabled.id}[href*='selection=true']")
    refute has_element?(view, "#branch-select-card-#{disabled.id}")

    selected =
      get(
        conn,
        "/staff/branches/select/#{enabled.id}?" <>
          URI.encode_query(%{"from" => source, "selection" => "true"})
      )

    assert redirected_to(selected) == "/staff/b/#{enabled.slug}/analytics/sources?period=month"

    all = get(conn, "/staff/branches/all?" <> URI.encode_query(%{"from" => source}))
    assert redirected_to(all) == source
  end

  test "analytics chooser hides network choice without network permission", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["statistics.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id})

    chooser =
      DelivestWeb.StaffBranchPath.selection_path("/staff/statistics", "/staff/dashboard")

    {:ok, view, _} = live(conn, chooser)
    assert has_element?(view, "#branch-select-go-#{branch.id}")
    refute has_element?(view, "#branch-select-all")
  end
end
