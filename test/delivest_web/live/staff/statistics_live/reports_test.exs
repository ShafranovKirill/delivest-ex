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
    {:ok, analyst, _} = live(analyst_conn, ~p"/staff/statistics")
    refute has_element?(analyst, "#statistics-report")

    manager_conn = login(conn, ["statistics.read", "statistics.network"], branch)

    {:ok, manager, _} =
      live(manager_conn, ~p"/staff/statistics?period=today")

    assert has_element?(manager, "#statistics-report")
    assert has_element?(manager, "#statistics-report-state")
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
        ~p"/staff/b/#{branch}/statistics?tab=funnel&period=today"
      )

    assert has_element?(view, "#statistics-funnel-path", "Sessions started")
    assert has_element?(view, "#statistics-funnel-path", "Visits")
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
        ~p"/staff/b/#{branch}/statistics?tab=channels&period=today"
      )

    assert has_element?(view, "#statistics-report-summary", "Average check")
    assert has_element?(view, "#statistics-report-summary", OrderHelpers.money(750))
    assert has_element?(view, "#statistics-report-summary", "Cancelled")
    assert has_element?(view, "#statistics-report-summary", "Refunded")
    assert has_element?(view, "#statistics-report-table", "App")
    assert has_element?(view, ~s{select[name="channel"] option}, "App")
    refute has_element?(view, ~s{input[name="channel"]})
    refute has_element?(view, "#statistics-report-table td", "channel")
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
    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/statistics?tab=sources&period=today")
    assert has_element?(view, ~s{select[name="link_id"] option}, "Autumn offer")
    assert has_element?(view, ~s{input[name="link_search"]})
    refute has_element?(view, ~s{input[name="link_id"]})
  end

  test "switching report tabs resets page while preserving filters and pager links", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    other_branch = insert(:branch, is_active: true)

    for feature <- ["analytics_extended", "analytics_links"] do
      assert {:ok, _} = Features.configure(feature, :franchise, true, actor: "host")
      assert {:ok, _} = Features.configure(feature, {:branch, branch.id}, true, actor: "host")
    end

    published(
      branch,
      "analytics_extended",
      for(
        index <- 1..51,
        do: {"extended", "channel", "channel-#{index}", %{"created" => 1}}
      )
    )

    link =
      Repo.insert!(%Delivest.Advertising.Link{
        branch_id: branch.id,
        token: Ecto.UUID.generate(),
        campaign: "summer",
        name: "Source one"
      })

    published(branch, "analytics_links", [
      {"links", "link", link.id, %{"created" => 1}}
    ])

    day = LocalTime.today(LocalTime.timezone(branch.id)) |> Date.to_iso8601()
    conn = login(conn, ["statistics.read"], branch)

    {:ok, view, _} =
      live(
        conn,
        ~p"/staff/b/#{branch}/statistics?#{%{"tab" => "channels", "period" => "custom", "from" => day, "to" => day, "branch_id" => branch.id, "branch_ids" => [branch.id, other_branch.id], "link_search" => "summer"}}"
      )

    assert has_element?(view, "#statistics-report-pagination a[href*='page=2']", "Next")
    view |> element("#statistics-report-pagination a", "Next") |> render_click()
    assert has_element?(view, "#statistics-report-pagination", "2 / 2")

    tab = "a[role='tab'][href*='tab=sources']:not([href*='page='])"

    [_, header] =
      view
      |> element("#staff-page-header")
      |> render()
      |> then(&Regex.run(~r/<template[^>]*>(.*)<\/template>/s, &1))

    href =
      header
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(tab)
      |> LazyHTML.attribute("href")
      |> List.first()

    assert href
    query = href |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert query["period"] == "custom"
    assert query["from"] == day and query["to"] == day
    assert query["branch_id"] == branch.id
    assert query["link_search"] == "summer"

    branch_ids =
      href
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.query_decoder()
      |> Enum.filter(fn {key, _} -> String.starts_with?(key, "branch_ids") end)
      |> Enum.map(&elem(&1, 1))

    assert Enum.sort(branch_ids) == Enum.sort([branch.id, other_branch.id])
    refute Map.has_key?(query, "page")

    render_patch(view, href)
    assert has_element?(view, "#statistics-report-table", "Source one")
    refute has_element?(view, "#statistics-report-pagination")

    render_patch(
      view,
      ~p"/staff/b/#{branch}/statistics?tab=channels&period=today&page=2&channel=app&branch_id=#{branch.id}&link_id=#{link.id}&link_search=summer&branch_ids[]=#{branch.id}"
    )

    [_, header] =
      view
      |> element("#staff-page-header")
      |> render()
      |> then(&Regex.run(~r/<template[^>]*>(.*)<\/template>/s, &1))

    assert header
           |> LazyHTML.from_fragment()
           |> LazyHTML.query(
             "a[role='tab'][href*='tab=sources'][href*='channel=app'][href*='link_id=#{link.id}']:not([href*='page='])"
           )
           |> Enum.any?()
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
    {:ok, view, _} = live(admin_conn, ~p"/staff/b/#{branch}/statistics?tab=funnel&period=today")
    assert {:ok, _} = Features.configure("analytics_funnel", :franchise, false, actor: "host")
    assert render_click(element(view, "#statistics-rebuild")) =~ "Calculation could not be queued"
    render_patch(view, ~p"/staff/b/#{branch}/statistics?tab=funnel&period=today")
    refute has_element?(view, "#statistics-report")
  end
end
