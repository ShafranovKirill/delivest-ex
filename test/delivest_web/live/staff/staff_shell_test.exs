defmodule DelivestWeb.Staff.StaffShellTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  test "global header owns scope, search and mobile toggle; sidebar owns tasks and profile", %{
    conn: conn
  } do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/dashboard")

    assert has_element?(lv, "#main-sidebar #sidebar-home[href='/staff']")
    assert has_element?(lv, "#main-sidebar #sidebar-toggle[aria-controls='main-sidebar']")
    assert has_element?(lv, "#nav-section-main")
    assert has_element?(lv, "#nav-section-settings a[href='/staff/settings']")

    assert has_element?(
             lv,
             "#staff-header #header-branch[open=false], #staff-header #header-branch"
           )

    assert has_element?(lv, "#staff-header #command-palette-trigger")
    assert has_element?(lv, "#staff-header #header-sidebar-toggle[data-sidebar-toggle]")
    refute has_element?(lv, "#main-sidebar #header-branch")
    refute has_element?(lv, "#main-sidebar #command-palette-trigger")
    assert has_element?(lv, "#staff-profile-trigger[aria-expanded='false']")
    assert has_element?(lv, "#staff-profile-menu[hidden] #orders-sound-toggle")
    assert has_element?(lv, "#staff-profile-menu #header-push-toggle")
    assert has_element?(lv, "#staff-profile-menu a[href='/staff/auth/log_out']")
    assert has_element?(lv, "#staff-profile-menu #app-version")
  end

  test "limited staff keeps profile controls without order sound or settings", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["products.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id})

    {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/products")
    refute has_element?(lv, "#main-sidebar #header-new-orders")
    refute has_element?(lv, "#nav-section-settings")
    refute has_element?(lv, "#staff-profile-menu #orders-sound-toggle")
    assert has_element?(lv, "#staff-profile-menu #header-push-toggle")
  end

  test "page title and actions remain in page content", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id})

    {:ok, lv, _} = live(conn, ~p"/staff/branches")
    assert has_element?(lv, "main #staff-page-header h1", "Settings for branches")
    assert has_element?(lv, "main #staff-page-header-actions #create-branch")
    refute has_element?(lv, "#staff-header h1")
    refute has_element?(lv, "#branch-settings-list h1")
  end

  test "header scope follows URL rather than a saved branch", %{conn: conn} do
    center = insert(:branch, name: "Center")
    north = insert(:branch, name: "North")
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    insert(:staff_branch, staff: staff, branch: center)
    insert(:staff_branch, staff: staff, branch: north)
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => center.id})

    {:ok, global, _} = live(conn, ~p"/staff/settings")
    assert has_element?(global, "#staff-header #header-branch summary[aria-label='Network']")

    {:ok, edit, _} = live(conn, ~p"/staff/branches/#{north.slug}/edit")
    assert has_element?(edit, "#staff-header #header-branch summary[aria-label='North']")

    {:ok, delivery, _} = live(conn, ~p"/staff/b/#{center}/delivery/address")
    assert has_element?(delivery, "#staff-header #header-branch summary[aria-label='Center']")

    {:ok, dadata, _} = live(conn, ~p"/staff/b/#{center}/integrations/dadata")
    assert has_element?(dadata, "#staff-header #header-branch summary[aria-label='Network']")

    {:ok, scoped, _} = live(conn, ~p"/staff/b/#{center}/dashboard")
    assert has_element?(scoped, "#staff-header #header-branch summary[aria-label='Center']")
  end

  test "settings pages share one sidebar and keep their page content", %{conn: conn} do
    branch = insert(:branch, slug: "settings-nav-branch")
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    pages = [
      {"/staff/settings?branch=#{branch.slug}", "features", "#settings-feature-filter"},
      {"/staff/franchise/brand", "brand", "#franchise-settings-form"},
      {"/staff/branches/#{branch.slug}/edit", "branch_settings", "#branch-section-hours"},
      {"/staff/branches/#{branch.slug}/edit/hours", "hours", "#branch-form"},
      {"/staff/b/#{branch.slug}/integrations", "integrations", "#integration-frontpad"},
      {"/staff/b/#{branch.slug}/delivery", "delivery_settings", "#delivery-couriers-card"}
    ]

    navigation =
      Enum.map(pages, fn {path, active_id, content} ->
        {:ok, view, _} = live(conn, path)
        assert has_element?(view, "#settings-center > #settings-navigation")
        assert has_element?(view, "#settings-center > .min-w-0 #{content}")
        assert has_element?(view, "#settings-nav-#{active_id}[aria-current='page']")
        refute has_element?(view, "#staff-section-navigation")

        document = LazyHTML.from_fragment(render(view))
        assert Enum.count(LazyHTML.query(document, "#settings-navigation")) == 1

        ids = document |> LazyHTML.query("#settings-navigation a") |> LazyHTML.attribute("id")
        hrefs = document |> LazyHTML.query("#settings-navigation a") |> LazyHTML.attribute("href")
        {path, ids, hrefs}
      end)

    assert navigation |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> length() == 1
    direct_hrefs = navigation |> hd() |> elem(2)
    assert Enum.member?(direct_hrefs, "/staff/branches/#{branch.slug}/edit/hours")

    for {path, _ids, hrefs} <- navigation do
      if path == "/staff/franchise/brand" do
        assert Enum.member?(
                 hrefs,
                 DelivestWeb.StaffBranchPath.selection_path(
                   "/staff/branches/#{branch.slug}/edit/hours",
                   path
                 )
               )
      else
        assert hrefs == direct_hrefs
      end
    end
  end

  test "settings navigation never uses an inaccessible branch", %{conn: conn} do
    allowed = insert(:branch, slug: "allowed-settings")
    denied = insert(:branch, slug: "denied-settings")

    staff =
      insert(:staff, role: insert(:role, permissions: ["franchise.update", "branches.read"]))

    insert(:staff_branch, staff: staff, branch: allowed)
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => denied.id})

    for path <- ["/staff/settings", "/staff/franchise/brand"] do
      {:ok, view, _} = live(conn, path)
      assert has_element?(view, "#settings-center > #settings-navigation")

      assert has_element?(
               view,
               "#settings-nav-branch_settings[href^='/staff/branches/select?'][href*='from=%2Fstaff%2Fbranches%2F#{allowed.slug}%2Fedit']"
             )

      refute has_element?(view, "#settings-navigation a[href*='#{denied.slug}']")
      refute has_element?(view, "#settings-nav-integrations")
    end
  end

  test "network overview does not show a saved branch order bell", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    {:ok, network, _} = live(conn, ~p"/staff/dashboard")
    refute has_element?(network, "#main-sidebar #header-new-orders")
    {:ok, scoped, _} = live(conn, ~p"/staff/b/#{branch}/dashboard")
    assert has_element?(scoped, "#main-sidebar #header-new-orders")
  end
end
