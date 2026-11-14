defmodule DelivestWeb.Staff.CommonNavigationTest do
  use DelivestWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Features
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Crm.BranchSettings
  alias Delivest.Repo

  defp login(conn, permissions, branches, active_branch_id \\ nil) do
    staff = insert(:staff, role: insert(:role, permissions: permissions))
    Enum.each(branches, &insert(:staff_branch, staff: staff, branch: &1))

    session = %{"staff_id" => staff.id}

    session =
      if active_branch_id,
        do: Map.put(session, "active_branch_id", active_branch_id),
        else: session

    init_test_session(conn, session)
  end

  test "global statistics renders franchise report without an active branch", %{conn: conn} do
    branch = insert(:branch)
    {:ok, _} = Features.configure("analytics_franchise", :franchise, true, actor: "test")

    {:ok, _} =
      Features.configure("analytics_franchise", {:branch, branch.id}, true, actor: "test")

    conn = login(conn, ["statistics.read", "statistics.network"], [branch])

    {:ok, view, _} = live(conn, ~p"/staff/statistics?period=today")
    assert has_element?(view, "#statistics-report")
    assert has_element?(view, "#statistics-scope a[href='/staff/statistics?period=today']")

    assert has_element?(
             view,
             "#statistics-scope a[href*='/staff/b/#{branch.slug}/statistics']"
           )
  end

  test "limited statistics role sees explicit branches but no franchise report", %{conn: conn} do
    branch = insert(:branch)
    conn = login(conn, ["statistics.read"], [branch])

    {:ok, view, _} = live(conn, ~p"/staff/statistics")
    assert has_element?(view, "#statistics-choose-branch")
    assert has_element?(view, "#staff-page-header h1")
    refute has_element?(view, "#staff-page-header [role='tablist']")
    refute has_element?(view, "#statistics-report")
    refute has_element?(view, "#statistics-scope a[href^='/staff/statistics']")

    assert has_element?(
             view,
             "#statistics-scope a[href*='/staff/b/#{branch.slug}/statistics']"
           )
  end

  test "statistics branch links preserve compatible filters but drop another branch link", %{
    conn: conn
  } do
    first = insert(:branch)
    second = insert(:branch)
    conn = login(conn, ["statistics.read"], [first, second], first.id)

    {:ok, _} = Features.configure("analytics_links", :franchise, true, actor: "test")
    {:ok, _} = Features.configure("analytics_links", {:branch, first.id}, true, actor: "test")
    {:ok, _} = Features.configure("analytics_links", {:branch, second.id}, true, actor: "test")

    {:ok, view, _} =
      live(
        conn,
        ~p"/staff/b/#{first}/statistics?tab=sources&period=custom&from=2026-11-01&to=2026-11-07&link_id=123"
      )

    assert has_element?(
             view,
             "#statistics-scope a[href*='#{second.slug}/statistics?'][href*='tab=sources'][href*='from=2026-11-01']:not([href*='link_id'])"
           )
  end

  test "marketing hub requires explicit allowed branch selection", %{conn: conn} do
    allowed = insert(:branch)
    denied = insert(:branch)
    conn = login(conn, ["stocks.read"], [allowed])

    {:ok, view, _} = live(conn, ~p"/staff/marketing")
    assert has_element?(view, "#marketing-choose-branch")
    assert has_element?(view, "#staff-page-header h1")

    assert has_element?(
             view,
             "#staff-section-navigation a[href^='/staff/branches/select?'][href*='from=%2Fstaff%2Fb%2F#{allowed.slug}%2Fstocks']"
           )

    refute has_element?(view, "#marketing-navigation")

    assert has_element?(
             view,
             "#marketing-branches a[href='/staff/marketing?branch=#{allowed.slug}']"
           )

    {:ok, selected, _} = live(conn, ~p"/staff/marketing?branch=#{allowed.slug}")

    assert has_element?(
             selected,
             "#staff-section-navigation a[href^='/staff/branches/select?'][href*='from=%2Fstaff%2Fb%2F#{allowed.slug}%2Fstocks']"
           )

    {:ok, rejected, _} = live(conn, ~p"/staff/marketing?branch=#{denied.slug}")
    refute has_element?(rejected, "#staff-section-navigation a[href*='/#{denied.slug}/stocks']")

    assert has_element?(
             rejected,
             "#staff-section-navigation a[href^='/staff/branches/select?'][href*='from=%2Fstaff%2Fb%2F#{allowed.slug}%2Fstocks']"
           )
  end

  test "network marketing keeps permitted branch areas and segments live under clients", %{
    conn: conn
  } do
    branch = insert(:branch)
    {:ok, _} = Features.configure("marketing_policies", :franchise, true, actor: "test")
    {:ok, _} = Features.configure("analytics_links", :franchise, true, actor: "test")
    {:ok, _} = Features.configure("analytics_links", {:branch, branch.id}, true, actor: "test")
    {:ok, _} = Features.configure("segments", :franchise, true, actor: "test")
    {:ok, _} = Features.configure("segments", {:branch, branch.id}, true, actor: "test")

    conn =
      login(
        conn,
        ~w(marketing.read stocks.read statistics.read franchise.update clients.read segments.read segments.network),
        [branch]
      )

    for path <- [~p"/staff/marketing/policies", ~p"/staff/marketing/bonuses"] do
      {:ok, view, _} = live(conn, path)

      assert has_element?(
               view,
               "#staff-section-navigation a[href^='/staff/branches/select?'][href*='from=%2Fstaff%2Fb%2F#{branch.slug}%2Fstocks']"
             )

      assert has_element?(
               view,
               "#staff-section-navigation a[href^='/staff/branches/select?'][href*='from=%2Fstaff%2Fb%2F#{branch.slug}%2Fadvertising-links']"
             )

      refute has_element?(view, "#marketing-navigation")

      {:ok, scoped, _} = live(conn, path <> "?branch=#{branch.slug}")

      assert has_element?(
               scoped,
               "#staff-section-navigation a[href^='/staff/branches/select?'][href*='from=%2Fstaff%2Fb%2F#{branch.slug}%2Fstocks']"
             )

      assert has_element?(
               scoped,
               "#staff-section-navigation a[href^='/staff/branches/select?'][href*='from=%2Fstaff%2Fb%2F#{branch.slug}%2Fadvertising-links']"
             )
    end

    {:ok, clients, _} = live(conn, ~p"/staff/clients")

    assert has_element?(
             clients,
             "#staff-section-navigation a[href='/staff/clients'][aria-current='page']"
           )

    assert has_element?(clients, "#staff-section-navigation a[href='/staff/segments']")

    {:ok, segments, _} = live(conn, ~p"/staff/segments")

    assert has_element?(
             segments,
             "#staff-section-navigation a[href='/staff/segments'][aria-current='page']"
           )

    assert has_element?(segments, "#staff-section-navigation a[href='/staff/clients']")
    refute has_element?(segments, "#marketing-navigation")
  end

  test "policy list has its own route and branch screen has common marketing nav", %{conn: conn} do
    branch = insert(:branch)
    {:ok, _} = Features.configure("marketing_policies", :franchise, true, actor: "test")
    conn = login(conn, ["marketing.read", "stocks.read"], [branch])

    {:ok, policies, _} = live(conn, ~p"/staff/marketing/policies")
    assert has_element?(policies, "#marketing-policies")
    assert has_element?(policies, "#staff-section-navigation")

    {:ok, stocks, _} = live(conn, ~p"/staff/b/#{branch}/stocks")
    assert has_element?(stocks, "#staff-section-navigation")

    assert has_element?(
             stocks,
             "#nav-section-main a[href='/staff/marketing/policies?branch=#{branch.slug}']"
           )

    assert has_element?(
             stocks,
             "#staff-section-navigation a[href='/staff/b/#{branch.slug}/stocks']"
           )

    refute has_element?(stocks, "#nav-section-common")
  end

  test "marketing branch selection hides CRM-owned loyalty", %{conn: conn} do
    branch = insert(:branch)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{enabled: true, provider: :frontpad}
    })

    conn = login(conn, ["promotions.read"], [branch])

    {:ok, view, _} = live(conn, ~p"/staff/marketing?branch=#{branch.slug}")

    assert has_element?(
             view,
             "#staff-section-navigation a[href^='/staff/branches/select?'][href*='from=%2Fstaff%2Fb%2F#{branch.slug}%2Fpromotions']"
           )

    refute has_element?(
             view,
             "#staff-section-navigation a[href='/staff/b/#{branch.slug}/loyalty']"
           )

    refute has_element?(view, "#marketing-navigation")
  end

  test "marketing sidebar group exposes all authorized areas in the current branch", %{conn: conn} do
    branch = insert(:branch)
    {:ok, _} = Features.configure("marketing_policies", :franchise, true, actor: "test")
    {:ok, _} = Features.configure("analytics_links", :franchise, true, actor: "test")
    {:ok, _} = Features.configure("analytics_links", {:branch, branch.id}, true, actor: "test")

    conn =
      login(
        conn,
        ~w(marketing.read stocks.read promotions.read statistics.read),
        [branch],
        branch.id
      )

    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/stocks")

    assert has_element?(
             view,
             "#nav-section-main a[href='/staff/marketing/policies?branch=#{branch.slug}']"
           )

    for path <- [
          "/staff/marketing/policies?branch=#{branch.slug}",
          "/staff/b/#{branch.slug}/stocks",
          "/staff/b/#{branch.slug}/promotions",
          "/staff/marketing/bonuses?branch=#{branch.slug}",
          "/staff/b/#{branch.slug}/advertising-links"
        ] do
      assert has_element?(view, "#staff-section-navigation a[href='#{path}']")
    end
  end

  test "marketing child without active branch keeps its section through branch selection", %{
    conn: conn
  } do
    branch = insert(:branch)
    conn = login(conn, ["stocks.read"], [branch])

    {:ok, view, _} = live(conn, ~p"/staff/marketing?section=stocks")
    assert has_element?(view, "#nav-section-main a[href='/staff/marketing?section=stocks']")
    assert has_element?(view, "#marketing-branches a[href='/staff/b/#{branch.slug}/stocks']")
    refute has_element?(view, "#nav-section-main a[href='/staff/b/#{branch.slug}/stocks']")
  end

  test "settings sidebar replaces branch, delivery and integration entries", %{conn: conn} do
    branch = insert(:branch)

    conn =
      login(
        conn,
        ["branches.read", "branches.update", "delivery.read", "integrations.read"],
        [branch],
        branch.id
      )

    {:ok, settings, _} = live(conn, ~p"/staff/settings")

    assert has_element?(
             settings,
             "#sidebar-group-settings[open] #sidebar-settings-nav-features[aria-current='page']"
           )

    refute has_element?(settings, "#nav-section-main a[href='/staff/branches']")
    refute has_element?(settings, "#nav-section-main a[href='/staff/integrations']")

    refute has_element?(
             settings,
             "#nav-section-main a[href='/staff/b/#{branch.slug}/delivery']"
           )

    {:ok, delivery, _} = live(conn, ~p"/staff/b/#{branch}/delivery")

    assert has_element?(
             delivery,
             "#sidebar-group-settings[open] #sidebar-settings-nav-delivery_settings[aria-current='page']"
           )

    assert has_element?(
             delivery,
             "#staff-page-header a[href='/staff/branches/#{branch.slug}/edit']"
           )

    {:ok, integrations, _} = live(conn, ~p"/staff/integrations")

    assert has_element?(
             integrations,
             "#sidebar-group-settings[open] #sidebar-settings-nav-integrations[aria-current='page']"
           )
  end

  test "diagnostics group opens on logs and keeps both entries", %{conn: conn} do
    conn = login(conn, ["logs.read"], [])
    {:ok, logs, _} = live(conn, ~p"/staff/logs")

    assert has_element?(logs, "#staff-context-navigation > #settings-navigation")
    assert has_element?(logs, "#settings-navigation a[aria-current='page']")
    assert has_element?(logs, "#settings-navigation a[href='/staff/diagnostics']")
    refute has_element?(logs, "#staff-section-navigation")
    refute has_element?(logs, "#nav-section-settings a[href='/staff/settings']")
  end

  test "product subpages keep Products active without duplicate sidebar links", %{conn: conn} do
    branch = insert(:branch)
    conn = login(conn, ["categories.read", "products.read"], [branch], branch.id)

    for path <- [~p"/staff/b/#{branch}/products/stops", ~p"/staff/b/#{branch}/menu/popular"] do
      {:ok, view, _} = live(conn, path)

      assert has_element?(view, "#nav-section-main")

      assert has_element?(view, "#nav-section-main a[href='/staff/b/#{branch.slug}/products']")
      active = if String.ends_with?(path, "/stops"), do: "stops", else: "popular"

      assert has_element?(
               view,
               "#sidebar-group-menu[open] #sidebar-product-section-tab-#{active}[aria-current='page']"
             )

      assert has_element?(view, "#sidebar-group-menu #sidebar-product-section-tab-stops")
      assert has_element?(view, "#sidebar-group-menu #sidebar-product-section-tab-popular")

      refute has_element?(
               view,
               "#nav-section-main > ul > li > a[href='/staff/b/#{branch.slug}/products/stops']"
             )

      refute has_element?(
               view,
               "#nav-section-main > ul > li > a[href='/staff/b/#{branch.slug}/menu/popular']"
             )

      assert has_element?(view, "#staff-section-navigation #product-section-tab-popular")
      assert has_element?(view, "#staff-section-navigation #product-section-tab-stops")

      assert Enum.count(
               LazyHTML.query(
                 LazyHTML.from_fragment(render(view)),
                 "#sidebar-product-section-tab-stops"
               )
             ) == 1

      assert Enum.count(
               LazyHTML.query(LazyHTML.from_fragment(render(view)), "#product-section-tab-stops")
             ) == 1
    end
  end
end
