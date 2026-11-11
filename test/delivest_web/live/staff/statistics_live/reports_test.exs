defmodule DelivestWeb.Staff.StatisticsLive.ReportsTest do
  use DelivestWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Features

  defp login(conn, permissions, branch) do
    staff = insert(:staff, role: insert(:role, permissions: permissions))
    insert(:staff_branch, staff: staff, branch: branch)
    init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
  end

  test "optional tabs are hidden and direct URL is downgraded when gates are off", %{conn: conn} do
    branch = insert(:branch)
    conn = login(conn, ["statistics.read"], branch)

    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/statistics?tab=funnel")
    refute has_element?(view, "#statistics-report")
    refute has_element?(view, ~s{a[href*="tab=funnel"]})
  end

  test "enabled funnel tab shows collection state and requires admin for rebuild", %{conn: conn} do
    branch = insert(:branch)
    assert {:ok, _} = Features.configure("analytics_funnel", :franchise, true, actor: "host")

    assert {:ok, _} =
             Features.configure("analytics_funnel", {:branch, branch.id}, true, actor: "host")

    analyst_conn = login(conn, ["statistics.read"], branch)

    {:ok, analyst, _} =
      live(analyst_conn, ~p"/staff/b/#{branch}/statistics?tab=funnel&period=today")

    assert has_element?(analyst, "#statistics-report-state", "Data was not collected")
    refute has_element?(analyst, "#statistics-rebuild")

    admin_conn = login(conn, ["admin"], branch)
    {:ok, admin, _} = live(admin_conn, ~p"/staff/b/#{branch}/statistics?tab=funnel&period=today")
    assert has_element?(admin, "#statistics-rebuild")
  end

  test "franchise tab needs network permission and feature gate", %{conn: conn} do
    branch = insert(:branch)
    assert {:ok, _} = Features.configure("analytics_franchise", :franchise, true, actor: "host")

    assert {:ok, _} =
             Features.configure("analytics_franchise", {:branch, branch.id}, true, actor: "host")

    analyst_conn = login(conn, ["statistics.read"], branch)
    {:ok, analyst, _} = live(analyst_conn, ~p"/staff/b/#{branch}/statistics?tab=franchise")
    refute has_element?(analyst, "#statistics-report")

    manager_conn = login(conn, ["statistics.read", "statistics.network"], branch)

    {:ok, manager, _} =
      live(manager_conn, ~p"/staff/b/#{branch}/statistics?tab=franchise&period=today")

    assert has_element?(manager, "#statistics-report")
    assert has_element?(manager, "#statistics-report-state")
  end
end
