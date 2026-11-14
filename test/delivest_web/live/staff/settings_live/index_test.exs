defmodule DelivestWeb.Staff.SettingsLive.IndexTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Integrations.Yookassa
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Crm.BranchSettings
  alias Delivest.Integrations.Frontpad
  alias Delivest.Repo

  defp login(conn, permissions) do
    staff = insert(:staff, role: insert(:role, permissions: permissions))
    init_test_session(conn, %{"staff_id" => staff.id})
  end

  test "admin settings uses persistent canonical navigation and feature filters", %{conn: conn} do
    branch = insert(:branch)
    {:ok, lv, _} = live(login(conn, ["admin"]), ~p"/staff/settings")

    assert has_element?(
             lv,
             "#settings-navigation #settings-nav-brand[href='/staff/franchise/brand']"
           )

    assert has_element?(lv, "#settings-navigation #settings-nav-branches[href='/staff/branches']")

    assert has_element?(
             lv,
             "#settings-navigation #settings-nav-integrations[href^='/staff/branches/select?']"
           )

    assert has_element?(lv, "#settings-nav-features[aria-current='page']")
    assert has_element?(lv, "#settings-feature-filter #settings-filter-disabled")
    assert has_element?(lv, "#feature-segments")
    assert has_element?(lv, "#feature-integration-zvonok")

    assert has_element?(
             lv,
             "#nav-section-main a[href^='/staff/branches/select?'][href*='from=%2Fstaff%2Fb%2F#{branch.slug}%2Forders']"
           )

    assert has_element?(
             lv,
             "#nav-section-main a[href^='/staff/branches/select?'][href*='from=%2Fstaff%2Fb%2F#{branch.slug}%2Fproducts']"
           )

    refute has_element?(lv, "[id^='settings-branch-card-']")
  end

  test "branches.read alone exposes the branch registry without unrelated settings", %{conn: conn} do
    {:ok, lv, _} = live(login(conn, ["branches.read"]), ~p"/staff/settings")
    assert has_element?(lv, "#settings-nav-branches")
    refute has_element?(lv, "#settings-nav-brand")
    refute has_element?(lv, "#settings-nav-integrations")
  end

  test "delivery.read alone keeps the branch registry reachable", %{conn: conn} do
    {:ok, lv, _} = live(login(conn, ["delivery.read"]), ~p"/staff/settings")
    assert has_element?(lv, "#settings-nav-branches[href='/staff/branches']")
    refute has_element?(lv, "#settings-nav-brand")
    refute has_element?(lv, "#settings-nav-integrations")
  end

  test "integrations.read alone exposes integration summary and canonical section", %{conn: conn} do
    {:ok, lv, _} = live(login(conn, ["integrations.read"]), ~p"/staff/settings")
    assert has_element?(lv, "#settings-nav-integrations")
    assert has_element?(lv, "#feature-integration-zvonok")
    refute has_element?(lv, "#settings-nav-brand")
    refute has_element?(lv, "#settings-nav-branches")
  end

  test "saved payment key does not imply payment usage in a branch", %{conn: conn} do
    branch = insert(:branch)
    Repo.insert!(%Yookassa.Settings{shop_id: "506751", secret_key: "saved-key"})
    {:ok, lv, _} = live(login(conn, ["admin"]), "/staff/settings?branch=#{branch.slug}")

    assert has_element?(lv, "#feature-integration-yookassa .badge", "Disabled")
    assert has_element?(lv, "#feature-integration-yookassa-usage")
    assert has_element?(lv, "#settings-scope", branch.name)
  end

  test "CRM order source configuration alone does not enable integration", %{conn: conn} do
    branch = insert(:branch)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{provider: :frontpad, frontpad: %Frontpad.Settings{api_key: "key"}}
    })

    {:ok, lv, _} = live(login(conn, ["admin"]), "/staff/settings?branch=#{branch.slug}")
    assert has_element?(lv, "#feature-integration-frontpad .badge", "Disabled")
    assert has_element?(lv, "#feature-integration-frontpad-usage", "Order sources")
  end

  test "URL branch beats saved preference for scope and sidebar destinations", %{conn: conn} do
    saved = insert(:branch)
    selected = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))

    conn =
      init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => saved.id})

    {:ok, scoped, _} = live(conn, "/staff/settings?branch=#{selected.slug}")
    assert has_element?(scoped, "#header-branch summary[aria-label='#{selected.name}']")
    assert has_element?(scoped, "#nav-section-main a[href='/staff/b/#{selected.slug}/dashboard']")
    assert has_element?(scoped, "#nav-section-main a[href='/staff/b/#{selected.slug}/orders']")

    {:ok, network, _} = live(conn, ~p"/staff/franchise/brand")
    assert has_element?(network, "#header-branch summary[aria-label='Network']")
    assert has_element?(network, "#nav-section-main a[href='/staff/dashboard']")

    assert has_element?(
             network,
             "#nav-section-main a[href^='/staff/branches/select?'][href*='from=%2Fstaff%2Fb%2F#{saved.slug}%2Forders']"
           )
  end

  test "inaccessible branch query exits to the network summary", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/staff/settings?filter=all", flash: flash}}} =
             live(login(conn, ["admin"]), "/staff/settings?branch=missing-branch")

    assert flash["error"] == "Permission denied"
  end
end
