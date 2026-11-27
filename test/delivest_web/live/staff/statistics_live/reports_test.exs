defmodule DelivestWeb.Staff.StatisticsLive.ReportsTest do
  use DelivestWeb.ConnCase, async: false

  @moduletag :repeatable_read

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.{Features, LocalTime, Repo}
  alias Delivest.Advertising.Links
  alias Delivest.Analytics.Reports.Query
  alias DelivestWeb.Staff.OrderLive.OrderHelpers
  alias DelivestWeb.Staff.StatisticsLive.{Index, ReportComponents}

  defp login(conn, permissions, branch) do
    staff = insert(:staff, role: insert(:role, permissions: permissions))
    insert(:staff_branch, staff: staff, branch: branch)
    init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
  end

  defp published(branch, feature, rows) do
    day = LocalTime.today(LocalTime.timezone(branch.id))
    snapshot = Ecto.UUID.generate()
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Repo.query!(
      "INSERT INTO analytics_report_snapshots(id,feature,branch_id,day,revision,franchise_generation,branch_generation,source_asof,inserted_at) VALUES ($1::text::uuid,$2,$3::text::uuid,$4,0,1,1,$5,$5)",
      [snapshot, feature, branch.id, day, now]
    )

    Repo.query!(
      "INSERT INTO analytics_report_states(feature,branch_id,day,revision,snapshot_id,published_at,source_asof,inserted_at,updated_at) VALUES ($1,$2::text::uuid,$3,0,$4::text::uuid,$5,$5,$5,$5)",
      [feature, branch.id, day, snapshot, now]
    )

    for {family, dimension, key, counts} <- rows do
      Repo.query!(
        "INSERT INTO analytics_report_rows(snapshot_id,family,dimension,key,counts) VALUES ($1::text::uuid,$2,$3,$4,$5::text::jsonb)",
        [snapshot, family, dimension, key, Jason.encode!(counts)]
      )
    end
  end

  test "optional tabs are hidden and direct URL is downgraded when gates are off", %{conn: conn} do
    branch = insert(:branch)
    conn = login(conn, ["statistics.read"], branch)

    assert {:error, {:redirect, %{to: destination}}} =
             live(conn, ~p"/staff/b/#{branch}/analytics/funnel")

    assert destination == "/staff/dashboard"
  end

  test "enabled funnel shows collection state without manual calculation controls", %{conn: conn} do
    branch = insert(:branch)
    assert {:ok, _} = Features.configure("analytics_funnel", :franchise, true, actor: "host")

    assert {:ok, _} =
             Features.configure("analytics_funnel", {:branch, branch.id}, true, actor: "host")

    analyst_conn = login(conn, ["statistics.read"], branch)

    {:ok, analyst, _} =
      live(analyst_conn, ~p"/staff/b/#{branch}/analytics/funnel?period=today")

    assert has_element?(analyst, "#statistics-report-state")
    refute has_element?(analyst, "#statistics-rebuild")

    admin_conn = login(conn, ["admin"], branch)
    {:ok, admin, _} = live(admin_conn, ~p"/staff/b/#{branch}/analytics/funnel?period=today")
    refute has_element?(admin, "#statistics-rebuild")
  end

  test "franchise tab needs network permission and feature gate", %{conn: conn} do
    branch = insert(:branch)
    assert {:ok, _} = Features.configure("analytics_franchise", :franchise, true, actor: "host")

    assert {:ok, _} =
             Features.configure("analytics_franchise", {:branch, branch.id}, true, actor: "host")

    analyst_conn = login(conn, ["statistics.read"], branch)
    assert {:error, {:redirect, _}} = live(analyst_conn, ~p"/staff/analytics/comparison")
    {:ok, analyst_branch, _} = live(analyst_conn, ~p"/staff/b/#{branch}/statistics")
    refute has_element?(analyst_branch, "#statistics-tab-franchise")
    manager_conn = login(conn, ["statistics.read", "statistics.network"], branch)
    {:ok, manager, _} = live(manager_conn, ~p"/staff/analytics/comparison?period=today")
    assert has_element?(manager, "#statistics-report-state")
    refute has_element?(manager, "#statistics-scope")
    refute has_element?(manager, "select[name=branch_id]")
  end

  test "franchise ranking and exact table use filtered report branch rows", %{conn: conn} do
    branch = insert(:branch)
    assert {:ok, _} = Features.configure("analytics_franchise", :franchise, true, actor: "host")

    assert {:ok, _} =
             Features.configure("analytics_franchise", {:branch, branch.id}, true, actor: "host")

    published(branch, "analytics_extended", [
      {"extended", "channel", "app", %{"completed" => 42, "revenue" => 1400}},
      {"extended", "channel", "staff", %{"completed" => 2, "revenue" => 300}}
    ])

    conn = login(conn, ["statistics.read", "statistics.network"], branch)
    {:ok, view, _} = live(conn, ~p"/staff/analytics/comparison?period=today&channel=app")
    row = "#statistics-branch-#{branch.id}"

    assert has_element?(view, "#statistics-ranking-chart[data-chart]")

    assert has_element?(
             view,
             "#{row} td[data-column=branch]",
             ~r/^\s*#{Regex.escape(branch.name)}\s*$/
           )

    assert has_element?(view, "#{row} td[data-column=completed]", ~r/^\s*42\s*$/)
    refute has_element?(view, "#{row} td[data-column=completed]", ~r/^\s*44\s*$/)

    view
    |> element("#statistics-ranking-metric")
    |> render_change(%{"metric" => "orders_per_day"})

    assert_patch(view)
    assert has_element?(view, "#{row} td[data-column=per_day]", ~r/^\s*42\.00\s*$/)
  end

  test "branch franchise link stays hidden while the global feature is off", %{conn: conn} do
    branch = insert(:branch)
    conn = login(conn, ["statistics.read", "statistics.network"], branch)

    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/statistics")
    refute has_element?(view, "#statistics-tab-franchise")
    refute has_element?(view, "#sidebar-statistics-tab-franchise")
  end

  test "funnel stages render readable labels rather than storage keys", %{conn: conn} do
    branch = insert(:branch)
    assert {:ok, _} = Features.configure("analytics_funnel", :franchise, true, actor: "host")

    assert {:ok, _} =
             Features.configure("analytics_funnel", {:branch, branch.id}, true, actor: "host")

    published(branch, "analytics_funnel", [
      {"funnel", "stage", "session_started", %{"sessions" => 3}},
      {"funnel", "stage", "visit", %{"sessions" => 2}},
      {"funnel", "session_source", "direct", %{"sessions" => 2}},
      {"funnel", "session_source", "unknown", %{"sessions" => 1}},
      {"funnel", "order", "all", %{"created" => 1, "converted_sessions" => 1}}
    ])

    {:ok, view, _} =
      live(
        login(conn, ["statistics.read"], branch),
        ~p"/staff/b/#{branch}/analytics/funnel?period=today"
      )

    assert has_element?(view, "#statistics-funnel-path", "Sessions started")
    assert has_element?(view, "#statistics-funnel-path", "Menu views")

    assert has_element?(view, "#statistics-funnel-chart[data-chart]")
    assert has_element?(view, "#statistics-funnel-data")
    assert has_element?(view, "#statistics-funnel-sources", "Direct visit")
    assert has_element?(view, "#statistics-funnel-sources", "Unknown source")
    assert has_element?(view, "#statistics-funnel-sources", "unverified observations")
    refute render(view) =~ "session_started"

    day = LocalTime.today(LocalTime.timezone(branch.id))

    assert Query.read("analytics_funnel", [branch.id], day, day, "funnel", %{}, 1).totals[
             "sessions"
           ] == 3
  end

  test "channel summary uses weighted average and shows cancellations and refunds", %{conn: conn} do
    branch = insert(:branch)
    assert {:ok, _} = Features.configure("analytics_extended", :franchise, true, actor: "host")

    assert {:ok, _} =
             Features.configure("analytics_extended", {:branch, branch.id}, true, actor: "host")

    published(branch, "analytics_extended", [
      {"extended", "channel", "app",
       %{
         "created" => 3,
         "completed" => 2,
         "cancelled" => 1,
         "revenue" => 1_500,
         "refunded" => 500
       }}
    ])

    {:ok, view, _} =
      live(
        login(conn, ["statistics.read"], branch),
        ~p"/staff/b/#{branch}/analytics/channels?period=today"
      )

    refute has_element?(view, "#statistics-rebuild")
    refute has_element?(view, "#statistics-report-state", "Last successful check")
    refute has_element?(view, "#statistics-report-state", "Oldest successful bucket")
    assert has_element?(view, "#statistics-report-summary", "Average check")
    assert has_element?(view, "#statistics-report-summary", OrderHelpers.money(750))
    assert has_element?(view, "#statistics-report-summary", "Cancelled")
    assert has_element?(view, "#statistics-report-summary", "Refunded")
    assert has_element?(view, "#statistics-report-rows-table", "Storefront")
    assert has_element?(view, ~s{select[name="channel"] option}, "Storefront")
    refute has_element?(view, ~s{input[name="channel"]})
    refute has_element?(view, "#statistics-report-rows-table td", "channel")
  end

  test "network channel totals include only authorized feature-enabled branches" do
    allowed = insert(:branch)
    disabled = insert(:branch)
    denied = insert(:branch)

    staff =
      insert(:staff, role: insert(:role, permissions: ["statistics.read", "statistics.network"]))

    for branch <- [allowed, disabled], do: insert(:staff_branch, staff: staff, branch: branch)
    staff = Repo.preload(staff, [:role, :branches])
    assert {:ok, _} = Features.configure("analytics_extended", :franchise, true, actor: "host")

    for branch <- [allowed, denied] do
      assert {:ok, _} =
               Features.configure("analytics_extended", {:branch, branch.id}, true, actor: "host")

      published(branch, "analytics_extended", [
        {"extended", "channel", "app", %{"created" => 3, "completed" => 2, "revenue" => 1500}}
      ])
    end

    today = LocalTime.today(LocalTime.timezone(allowed.id))

    assert {:ok, report} =
             Delivest.Analytics.Reports.read(staff, :network, {today, today}, "channels")

    assert report.totals["revenue"] == 1500
    assert report.excluded_branches == 1
  end

  test "sources use a bounded human link selector", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    assert {:ok, _} = Features.configure("analytics_links", :franchise, true, actor: "host")

    assert {:ok, _} =
             Features.configure("analytics_links", {:branch, branch.id}, true, actor: "host")

    staff = insert(:staff, role: insert(:role, permissions: ["statistics.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    staff = Repo.preload(staff, [:role, :branches])

    assert {:ok, _} =
             Links.create(staff, branch.id, %{"name" => "Autumn offer", "campaign" => "season"})

    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/analytics/sources?period=today")
    assert has_element?(view, ~s{select[name="link_id"] option}, "Autumn offer")
    assert has_element?(view, ~s{input[name="link_search"]})
    refute has_element?(view, ~s{input[name="link_id"]})
  end

  test "legacy report URLs redirect preserving the period and filters", %{conn: conn} do
    branch = insert(:branch)
    conn = login(conn, ["statistics.read"], branch)

    assert {:error, {:redirect, %{to: destination}}} =
             live(
               conn,
               ~p"/staff/b/#{branch}/statistics?tab=channels&period=custom&from=2026-11-01&to=2026-11-07&channel=app&page=2"
             )

    assert URI.parse(destination).path == "/staff/b/#{branch.slug}/analytics/channels"
    query = URI.decode_query(URI.parse(destination).query)
    assert query["period"] == "custom"
    assert query["from"] == "2026-11-01"
    assert query["to"] == "2026-11-07"
    assert query["channel"] == "app"
    assert query["page"] == "2"
    refute Map.has_key?(query, "tab")
  end

  test "unavailable report DTO renders after a gate or read failure", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["statistics.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    staff = Repo.preload(staff, [:role, :branches])

    html =
      render_component(&ReportComponents.report_panel/1,
        tab: "channels",
        title: "Channels",
        report: Index.unavailable_report(),
        current_staff: staff,
        current_branch: branch,
        staff_branches: [branch],
        page_path: fn _ -> "/" end
      )

    assert html =~ "Data was not collected"
    assert html =~ "Average check"

    assert {:ok, _} = Features.configure("analytics_funnel", :franchise, true, actor: "host")

    assert {:ok, _} =
             Features.configure("analytics_funnel", {:branch, branch.id}, true, actor: "host")

    admin_conn = login(conn, ["admin"], branch)
    {:ok, view, _} = live(admin_conn, ~p"/staff/b/#{branch}/analytics/funnel?period=today")
    assert {:ok, _} = Features.configure("analytics_funnel", :franchise, false, actor: "host")
    assert_redirect(view, ~p"/staff/b/#{branch}/statistics?period=today")
  end
end
