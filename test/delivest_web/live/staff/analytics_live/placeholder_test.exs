defmodule DelivestWeb.Staff.AnalyticsLive.PlaceholderTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Repo
  alias Delivest.Identity

  @sections ~w(channels sources funnel customers comparison)

  defp login(conn, permissions) do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: permissions))
    insert(:staff_branch, staff: staff, branch: branch)
    init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
  end

  test "all analytics placeholders show only an empty state and their own active link", %{
    conn: conn
  } do
    conn = login(conn, ["statistics.read", "statistics.network"])
    jobs_before = analytics_schedule_count()

    for section <- @sections do
      {:ok, view, _} = live(conn, "/staff/analytics/#{section}")

      assert has_element?(view, "#analytics-placeholder", "Section under development")
      assert has_element?(view, "#staff-page-header h1")
      assert has_element?(view, "#sidebar-group-analytics[open]")
      assert has_element?(view, "#sidebar-section-nav-analytics_#{section}[aria-current='page']")
      refute has_element?(view, "#statistics-report")
      refute has_element?(view, "#statistics-rebuild")

      active =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#sidebar-group-analytics [aria-current='page']")

      assert Enum.count(active) == 1
    end

    assert analytics_schedule_count() == jobs_before
  end

  test "invalid placeholder section redirects to working statistics", %{conn: conn} do
    conn = login(conn, ["statistics.read", "statistics.network"])

    assert {:error, {:live_redirect, %{to: "/staff/statistics"}}} =
             live(conn, "/staff/analytics/unknown")
  end

  test "read-only statistics role can still view reports but cannot see or open placeholders", %{
    conn: conn
  } do
    conn = login(conn, ["statistics.read"])
    {:ok, view, _} = live(conn, "/staff/statistics")
    assert has_element?(view, "#sidebar-section-nav-statistics[aria-current='page']")
    refute has_element?(view, "#sidebar-section-nav-analytics_channels")

    for section <- @sections do
      assert {:error, {:redirect, _}} = live(conn, "/staff/analytics/#{section}")
    end
  end

  test "network permission without read permission cannot open placeholders", %{conn: conn} do
    conn = login(conn, ["statistics.network"])
    assert {:error, {:redirect, _}} = live(conn, "/staff/analytics/channels")
  end

  test "only named placeholder paths are valid network return targets" do
    for section <- @sections do
      path = "/staff/analytics/#{section}"
      assert {:ok, %{path: ^path}} = DelivestWeb.StaffBranchPath.transition(path, :network)
    end

    assert :error = DelivestWeb.StaffBranchPath.transition("/staff/analytics/unknown", :network)
  end

  test "an open placeholder closes when the read permission is revoked", %{conn: conn} do
    branch = insert(:branch)
    role = insert(:role, permissions: ["statistics.read", "statistics.network"])
    staff = insert(:staff, role: role)
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    {:ok, view, _} = live(conn, "/staff/analytics/channels")
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))
    assert {:ok, _} = Identity.update_role(admin, role, %{permissions: ["statistics.network"]})

    assert_redirect(view, DelivestWeb.StaffBranchPath.home(branch))
  end

  defp analytics_schedule_count do
    Repo.query!("SELECT count(*) FROM background_schedules WHERE kind LIKE 'analytics.%'").rows
    |> hd()
    |> hd()
  end
end
