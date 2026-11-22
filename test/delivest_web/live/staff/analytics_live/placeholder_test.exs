defmodule DelivestWeb.Staff.AnalyticsLive.PlaceholderTest do
  use DelivestWeb.ConnCase, async: false

  @moduletag :repeatable_read

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Features

  defp login(conn, permissions) do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: permissions))
    insert(:staff_branch, staff: staff, branch: branch)
    {init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id}), branch}
  end

  defp enable_reports(branch) do
    for feature <- ~w(analytics_extended analytics_links analytics_funnel analytics_franchise) do
      assert {:ok, _} = Features.configure(feature, :franchise, true, actor: "host")
      assert {:ok, _} = Features.configure(feature, {:branch, branch.id}, true, actor: "host")
    end
  end

  test "network report destinations render existing reports", %{conn: conn} do
    {conn, branch} = login(conn, ["statistics.read", "statistics.network"])
    enable_reports(branch)

    for section <- ~w(channels sources funnel customers comparison) do
      {:ok, view, _} = live(conn, "/staff/analytics/#{section}")
      assert has_element?(view, "#statistics-report-state")
      refute has_element?(view, "#analytics-placeholder")
      refute has_element?(view, "#statistics-scope")
      assert has_element?(view, "#sidebar-group-analytics a[href='/staff/statistics']")
    end
  end

  test "branch-only analysts see branch reports and cannot open network reports", %{conn: conn} do
    {conn, branch} = login(conn, ["statistics.read"])
    enable_reports(branch)

    for section <- ~w(channels sources funnel customers) do
      {:ok, view, _} = live(conn, "/staff/b/#{branch.slug}/analytics/#{section}")
      assert has_element?(view, "#statistics-report-state")

      assert has_element?(
               view,
               "#sidebar-group-analytics a[href='/staff/b/#{branch.slug}/statistics']"
             )

      assert {:error, {:redirect, _}} = live(conn, "/staff/analytics/#{section}")
    end

    assert {:error, {:redirect, _}} = live(conn, "/staff/analytics/comparison")
  end

  test "branch switching preserves report and custom period without link scope", %{conn: _conn} do
    source =
      "/staff/b/first/analytics/sources?period=custom&from=2026-11-01&to=2026-11-07&channel=app&link_id=private"

    assert {:ok, %{path: path}} =
             DelivestWeb.StaffBranchPath.transition(source, {:branch, "second"})

    assert URI.parse(path).path == "/staff/b/second/analytics/sources"
    query = URI.decode_query(URI.parse(path).query)
    assert query["period"] == "custom"
    assert query["from"] == "2026-11-01"
    assert query["to"] == "2026-11-07"
    refute query["link_id"]
    assert {:ok, %{path: network}} = DelivestWeb.StaffBranchPath.transition(source, :network)
    assert URI.parse(network).path == "/staff/analytics/sources"
  end

  test "invalid report section redirects to statistics", %{conn: conn} do
    {conn, _} = login(conn, ["statistics.read", "statistics.network"])

    assert {:error, {:redirect, %{to: "/staff/statistics"}}} =
             live(conn, "/staff/analytics/unknown")
  end

  test "network campaign navigation ignores a remembered branch", %{conn: conn} do
    {conn, _branch} = login(conn, ["statistics.read", "statistics.network"])
    {:ok, view, _} = live(conn, "/staff/analytics/advertising")

    assert has_element?(view, "#sidebar-group-analytics a[href='/staff/statistics']")

    refute has_element?(view, "#sidebar-group-analytics a[href^='/staff/branches/select']")
  end
end
