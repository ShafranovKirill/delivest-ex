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
    assert has_element?(view, "#statistics-scope a[href*='/staff/b/#{branch.slug}/statistics']")
  end

  test "limited statistics role sees explicit branches but no franchise report", %{conn: conn} do
    branch = insert(:branch)
    conn = login(conn, ["statistics.read"], [branch])

    {:ok, view, _} = live(conn, ~p"/staff/statistics")
    assert has_element?(view, "#statistics-choose-branch")
    refute has_element?(view, "#statistics-report")
    refute has_element?(view, "#statistics-scope a[href^='/staff/statistics']")
    assert has_element?(view, "#statistics-scope a[href*='/staff/b/#{branch.slug}/statistics']")
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
    refute has_element?(view, "#marketing-navigation a[href*='/stocks']")

    assert has_element?(
             view,
             "#marketing-branches a[href='/staff/marketing?branch=#{allowed.slug}']"
           )

    {:ok, selected, _} = live(conn, ~p"/staff/marketing?branch=#{allowed.slug}")

    assert has_element?(
             selected,
             "#marketing-navigation a[href='/staff/b/#{allowed.slug}/stocks']"
           )

    {:ok, rejected, _} = live(conn, ~p"/staff/marketing?branch=#{denied.slug}")
    refute has_element?(rejected, "#marketing-navigation a[href*='/stocks']")
  end

  test "policy list has its own route and branch screen has common marketing nav", %{conn: conn} do
    branch = insert(:branch)
    {:ok, _} = Features.configure("marketing_policies", :franchise, true, actor: "test")
    conn = login(conn, ["marketing.read", "stocks.read"], [branch])

    {:ok, policies, _} = live(conn, ~p"/staff/marketing/policies")
    assert has_element?(policies, "#marketing-policies")
    assert has_element?(policies, "#marketing-navigation")

    {:ok, stocks, _} = live(conn, ~p"/staff/b/#{branch}/stocks")
    assert has_element?(stocks, "#marketing-navigation")
    assert has_element?(stocks, "#nav-section-network a[href='/staff/marketing']")
    refute has_element?(stocks, "#nav-section-common")
    refute has_element?(stocks, "#main-sidebar a[href='/staff/b/#{branch.slug}/stocks']")
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
             "#marketing-navigation a[href='/staff/b/#{branch.slug}/promotions']"
           )

    refute has_element?(view, "#marketing-navigation a[href='/staff/b/#{branch.slug}/loyalty']")
  end
end
