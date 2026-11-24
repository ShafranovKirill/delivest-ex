defmodule DelivestWeb.Staff.SettingsLive.IndexTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory
  alias Delivest.Features
  alias Delivest.Features.Settings
  alias Delivest.Identity.Branch.BranchInfo

  test "disabled optional section disappears from navigation and rejects its direct URL", %{
    conn: conn
  } do
    branch = insert(:branch)

    assert {:ok, _} =
             Features.configure("kitchen", {:branch, branch.id}, false, actor: "test")

    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id})

    {:ok, orders, _} = live(conn, ~p"/staff/b/#{branch}/orders")
    refute has_element?(orders, "#main-sidebar a[href='/staff/b/#{branch.slug}/kitchen']")

    refute has_element?(
             orders,
             "#staff-context-navigation a[href='/staff/b/#{branch.slug}/kitchen']"
           )

    assert {:error, {:redirect, %{to: "/staff/dashboard"}}} =
             live(conn, ~p"/staff/b/#{branch}/kitchen")

    {:ok, settings, _} = live(conn, ~p"/staff/settings")
    assert has_element?(settings, "#feature-toggle-kitchen")
  end

  test "toggling an add-on refreshes open core navigation without leaving the order page", %{
    conn: conn
  } do
    branch = insert(:branch)
    Delivest.Repo.insert!(%BranchInfo{branch_id: branch.id, kitchen: %{enabled: true}})
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id})

    {:ok, orders, _} = live(conn, ~p"/staff/b/#{branch}/orders")
    assert has_element?(orders, "a[href='/staff/b/#{branch.slug}/kitchen']")

    {:ok, preview} = Features.disable_preview("kitchen", {:branch, branch.id})
    assert {:ok, _} = Settings.configure(staff, "kitchen", {:branch, branch.id}, false, preview)
    refute Features.enabled?("kitchen", {:branch, branch.id})

    refute inspect(DelivestWeb.StaffNav.entries(staff, branch)) =~
             "/staff/b/#{branch.slug}/kitchen"

    assert has_element?(orders, "#main-sidebar[data-capability-revision='1']")
    refute has_element?(orders, "#main-sidebar a[href='/staff/b/#{branch.slug}/kitchen']")
    assert has_element?(orders, "#nav-section-main")
  end

  defp login(conn, permissions) do
    staff = insert(:staff, role: insert(:role, permissions: permissions))
    init_test_session(conn, %{"staff_id" => staff.id})
  end

  test "admin settings uses persistent canonical navigation without duplicate scope or filters",
       %{conn: conn} do
    insert(:branch)
    {:ok, lv, _} = live(login(conn, ["admin"]), ~p"/staff/settings")

    assert has_element?(
             lv,
             "#settings-navigation #settings-nav-franchise[href='/staff/franchise']"
           )

    assert has_element?(lv, "#settings-navigation #settings-nav-branches[href='/staff/branches']")

    assert has_element?(
             lv,
             "#settings-navigation #settings-nav-integrations[href^='/staff/branches/select?']"
           )

    assert has_element?(lv, "#settings-nav-features[aria-current='page']", "Capabilities")
    assert has_element?(lv, "#sidebar-settings-nav-features[aria-current='page']")

    assert has_element?(
             lv,
             "#settings-navigation #settings-nav-data_system[href='/staff/settings/data-system']"
           )

    refute has_element?(lv, "#settings-navigation > #settings-nav-data_transfer")
    refute has_element?(lv, "#settings-nav-delivery_settings")

    refute has_element?(lv, "#settings-navigation #settings-nav-instance_backup")
    refute has_element?(lv, "#settings-navigation #settings-nav-site_snapshot")

    refute has_element?(lv, "#settings-navigation #settings-nav-hours")
    refute has_element?(lv, "#settings-navigation #settings-nav-delivery_zones")
    refute has_element?(lv, "#settings-navigation #settings-nav-order_settings")
    refute has_element?(lv, "#settings-navigation #settings-nav-loyalty_settings")
    refute has_element?(lv, "#settings-navigation #settings-nav-team")
    refute has_element?(lv, "#settings-navigation #settings-nav-roles_settings")
    refute has_element?(lv, "#settings-feature-filter")
    refute has_element?(lv, "#settings-scope")
    assert has_element?(lv, "#settings-group-marketing")
    assert has_element?(lv, "#settings-group-analytics")
    assert has_element?(lv, "#settings-group-integrations")
    assert has_element?(lv, "#feature-integration_yandex_ads")
    assert has_element?(lv, "#feature-integration_ycart")
    assert has_element?(lv, "#feature-toggle-integration_yandex_ads[aria-checked=true]")
    assert has_element?(lv, "#feature-yandex_ads")
    assert has_element?(lv, "#feature-yandex_browser")
    assert has_element?(lv, "#feature-toggle-segments[aria-checked=false]")
    assert has_element?(lv, "#feature-segments")
    refute has_element?(lv, "#settings-connections")

    assert has_element?(
             lv,
             "#nav-section-main a[href^='/staff/branches/select?'][href*='%2Forders']"
           )

    assert has_element?(
             lv,
             "#nav-section-main a[href^='/staff/branches/select?'][href*='%2Fproducts']"
           )

    refute has_element?(lv, "[id^='settings-branch-card-']")

    html = render(lv)
    {integrations_position, _} = :binary.match(html, "id=\"settings-nav-integrations\"")
    {capabilities_position, _} = :binary.match(html, "id=\"settings-nav-features\"")
    {data_position, _} = :binary.match(html, "id=\"settings-nav-data_system\"")
    assert integrations_position < capabilities_position and capabilities_position < data_position
  end

  test "integration permission changes are network-wide even on a branch page", %{conn: conn} do
    branch = insert(:branch)
    {:ok, lv, _} = live(login(conn, ["admin"]), "/staff/settings?branch=#{branch.slug}")

    assert has_element?(lv, "#feature-toggle-integration_yandex_ads[aria-checked=true]")
    render_click(element(lv, "#feature-toggle-integration_yandex_ads"))
    assert has_element?(lv, "#feature-confirmation", "Scope: network")

    assert has_element?(
             lv,
             "#feature-confirmation",
             "Existing connection activity will continue."
           )

    render_click(element(lv, "#feature-confirm"))

    assert has_element?(lv, "#feature-toggle-integration_yandex_ads[aria-checked=false]")

    assert has_element?(
             lv,
             "#feature-integration_yandex_ads button[disabled]",
             "Enable to open settings"
           )

    refute Delivest.Integrations.StaffAccess.allowed?(:yandex_ads)
  end

  test "branches.read alone exposes the branch registry without unrelated settings", %{conn: conn} do
    {:ok, lv, _} = live(login(conn, ["branches.read"]), ~p"/staff/settings")
    assert has_element?(lv, "#settings-nav-branches")
    refute has_element?(lv, "#feature-segments")
    refute has_element?(lv, "#settings-nav-franchise")
    refute has_element?(lv, "#settings-nav-integrations")
  end

  test "delivery.read alone keeps the branch registry reachable", %{conn: conn} do
    {:ok, lv, _} = live(login(conn, ["delivery.read"]), ~p"/staff/settings")
    assert has_element?(lv, "#settings-nav-branches[href='/staff/branches']")
    refute has_element?(lv, "#settings-nav-franchise")
    refute has_element?(lv, "#settings-nav-integrations")
  end

  test "integrations.read alone exposes the integrations navigation", %{conn: conn} do
    {:ok, lv, _} = live(login(conn, ["integrations.read"]), ~p"/staff/settings")
    assert has_element?(lv, "#settings-nav-integrations")
    refute has_element?(lv, "#settings-connections")
    refute has_element?(lv, "#feature-integration_yandex_ads")
    refute has_element?(lv, "#settings-nav-franchise")
    refute has_element?(lv, "#settings-nav-branches")
  end

  test "obsolete status filter does not hide features", %{conn: conn} do
    {:ok, lv, _} = live(login(conn, ["admin"]), "/staff/settings?filter=disabled")

    assert has_element?(lv, "#feature-couriers")
    assert has_element?(lv, "#feature-analytics_funnel")
    refute has_element?(lv, "#settings-feature-filter")
  end

  test "URL branch beats saved preference for scope and sidebar destinations", %{conn: conn} do
    saved = insert(:branch)
    selected = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))

    conn =
      init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => saved.id})

    {:ok, scoped, _} = live(conn, "/staff/settings?branch=#{selected.slug}")
    refute has_element?(scoped, "#settings-scope")

    assert has_element?(
             scoped,
             "#settings-nav-features[href='/staff/settings?branch=#{selected.slug}']"
           )

    assert has_element?(
             scoped,
             "#sidebar-settings-nav-features[href='/staff/settings?branch=#{selected.slug}']"
           )

    assert has_element?(
             scoped,
             "#header-branch-all[href^='/staff/branches/all?'][href*='from=%2Fstaff%2Fsettings']"
           )

    assert has_element?(
             scoped,
             "#feature-couriers a[href='/staff/b/#{selected.slug}/delivery/couriers']"
           )

    assert has_element?(
             scoped,
             "#feature-analytics_links button[disabled]",
             "Enable to open settings"
           )

    assert has_element?(scoped, "#header-branch summary[aria-label='#{selected.name}']")
    assert has_element?(scoped, "#nav-section-main a[href='/staff/b/#{selected.slug}/dashboard']")
    assert has_element?(scoped, "#nav-section-main a[href='/staff/b/#{selected.slug}/orders']")

    {:ok, network_settings, _} = live(conn, ~p"/staff/settings")
    assert has_element?(network_settings, "#settings-nav-features[href='/staff/settings']")

    assert has_element?(
             network_settings,
             "#sidebar-settings-nav-features[href='/staff/settings']"
           )

    assert has_element?(
             network_settings,
             "#header-branch-#{selected.id}[href^='/staff/branches/select/#{selected.id}?'][href*='from=%2Fstaff%2Fsettings']"
           )

    expected_branch_path = "/staff/settings?branch=#{selected.slug}"

    assert {:ok, %{path: ^expected_branch_path}} =
             DelivestWeb.StaffBranchPath.transition("/staff/settings", {:branch, selected.slug})

    assert {:ok, %{path: "/staff/settings"}} =
             DelivestWeb.StaffBranchPath.transition(
               "/staff/settings?branch=#{selected.slug}",
               :network
             )

    {:ok, network, _} = live(conn, ~p"/staff/franchise/brand")
    assert has_element?(network, "#header-branch summary[aria-label='Network']")
    assert has_element?(network, "#nav-section-main a[href='/staff/dashboard']")

    assert has_element?(
             network,
             "#nav-section-main a[href^='/staff/branches/select?'][href*='from=%2Fstaff%2Fb%2F#{saved.slug}%2Forders']"
           )
  end

  test "inaccessible branch query exits to the network summary", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/staff/settings", flash: flash}}} =
             live(login(conn, ["admin"]), "/staff/settings?branch=missing-branch")

    assert flash["error"] == "Permission denied"
  end
end
