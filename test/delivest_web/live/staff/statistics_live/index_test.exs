defmodule DelivestWeb.Staff.StatisticsLive.IndexTest do
  use DelivestWeb.ConnCase, async: false

  @moduletag :repeatable_read

  import Phoenix.LiveViewTest
  import Delivest.Factory
  import Delivest.OrderFixtures

  defp login(conn, permissions) do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: permissions))
    insert(:staff_branch, staff: staff, branch: branch)

    {init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id}), branch}
  end

  defp completed(order) do
    order
    |> Ecto.Changeset.change(status: :completed)
    |> Delivest.Repo.update!()
  end

  test "shows sales, products and categories of the branch", %{conn: conn} do
    {conn, branch} = login(conn, ["statistics.read"])
    category = insert(:category, name: "Горячее")

    product =
      insert_branch_product(branch.id, name: "Хинкали", price: 30_000, category_id: category.id)

    branch.id |> order_fixture(product: product, quantity: 2) |> completed()

    {:ok, lv, html} = live(conn, ~p"/staff/b/#{branch}/statistics")
    assert html =~ "Sales"
    assert html =~ "600 ₽"
    assert has_element?(lv, "#statistics-filter option[value=month][selected]")
    assert has_element?(lv, "#statistics-sales-detail")

    refute has_element?(lv, "#statistics-heatmap-link")
    assert has_element?(lv, "#statistics-heatmap-chart[data-chart]")

    refute has_element?(lv, "#statistics-sales-tabs")
    assert has_element?(lv, "#statistics-chart-revenue")

    assert has_element?(
             lv,
             "#statistics-sales-detail .statistics-metric-card .statistics-metric-label"
           )

    assert has_element?(
             lv,
             "#statistics-sales-detail .statistics-metric-card .statistics-metric-icon"
           )

    assert has_element?(lv, "#statistics-chart-revenue.statistics-panel")
    assert has_element?(lv, "#statistics-chart-orders")
    assert has_element?(lv, "#statistics-chart-avg_check")
    assert has_element?(lv, "#statistics-chart-revenue-plot[data-chart]")
    assert has_element?(lv, "#statistics-chart-orders-plot[data-chart]")
    assert has_element?(lv, "#statistics-chart-avg_check-plot[data-chart]")
    assert has_element?(lv, "#statistics-chart-revenue-plot table td[data-series=selected]")
    assert has_element?(lv, "#statistics-sales-charts + #statistics-heatmap")
    assert has_element?(lv, "#statistics-top-products", "Хинкали")
    assert has_element?(lv, "#statistics-top-categories", "Горячее")
    assert has_element?(lv, "#statistics-order-source", "Storefront")

    html = render_patch(lv, ~p"/staff/b/#{branch}/statistics?tab=products&period=today")
    assert html =~ "Хинкали"

    html = render_patch(lv, ~p"/staff/b/#{branch}/statistics?tab=categories&period=today")
    assert html =~ "Горячее"
  end

  test "sales heatmap filters independent complete weeks and opens a cell detail", %{conn: conn} do
    {conn, branch} = login(conn, ["statistics.read"])
    {_, to} = Delivest.Analytics.OrderHeatmap.default_period({:branch, branch.id})
    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/statistics")

    view
    |> element("#statistics-heatmap-filter")
    |> render_change(%{
      "heatmap_from" => Date.to_iso8601(Date.add(to, -55)),
      "heatmap_to" => Date.to_iso8601(to),
      "fulfillment" => "pickup"
    })

    assert_patch(view)
    assert has_element?(view, "#statistics-sales-detail")

    assert has_element?(
             view,
             "#statistics-heatmap-filter select[name=fulfillment] option[value=pickup][selected]"
           )

    view |> element("#statistics-heatmap-data tbody tr:first-child button") |> render_click()
    assert has_element?(view, "#statistics-heatmap-detail tbody tr")
  end

  test "overview heatmap changes fulfillment and lazily opens zero-date details", %{conn: conn} do
    {conn, branch} = login(conn, ["statistics.read"])
    {_, to} = Delivest.Analytics.OrderHeatmap.default_period({:branch, branch.id})
    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/statistics?tab=overview")
    assert has_element?(view, "#statistics-heatmap-chart[data-chart]")
    assert has_element?(view, "#statistics-heatmap-data tbody tr")
    refute has_element?(view, "#statistics-heatmap-detail")

    view
    |> element("#statistics-heatmap-filter")
    |> render_change(%{
      "heatmap_from" => Date.to_iso8601(Date.add(to, -55)),
      "heatmap_to" => Date.to_iso8601(to),
      "fulfillment" => "pickup"
    })

    assert_patch(view)

    assert has_element?(
             view,
             "#statistics-heatmap-filter select[name=fulfillment] option[value=pickup][selected]"
           )

    view |> element("#statistics-heatmap-data tbody tr:first-child button") |> render_click()
    assert has_element?(view, "#statistics-heatmap-detail tbody tr")
  end

  test "overview rejects partial-week heatmap date range", %{conn: conn} do
    {conn, branch} = login(conn, ["statistics.read"])

    {:ok, view, _} =
      live(
        conn,
        ~p"/staff/b/#{branch}/statistics?tab=overview&heatmap_from=2026-10-27&heatmap_to=2026-11-22"
      )

    assert has_element?(view, "#statistics-heatmap-period-error")
    refute has_element?(view, "#statistics-heatmap-data tbody tr")
    render_hook(view, "heatmap_detail", %{"day" => "1", "hour" => "12"})
    refute has_element?(view, "#statistics-heatmap-detail")
  end

  test "monthly chart uses weighted average check and retains signed revenue" do
    daily = [
      %{date: ~D[2026-11-01], revenue: 20_000, orders: 1},
      %{date: ~D[2026-11-02], revenue: -5_000, orders: 2},
      %{date: ~D[2026-12-01], revenue: 6_000, orders: 1}
    ]

    assert [november, december] =
             DelivestWeb.Staff.StatisticsLive.SalesChart.buckets(daily, "month")

    assert november == %{
             from: ~D[2026-11-01],
             to: ~D[2026-11-02],
             revenue: 15_000,
             orders: 3,
             avg_check: 5_000
           }

    assert december.revenue == 6_000
  end

  test "weekly chart follows Monday boundaries across months and years" do
    daily = [
      %{date: ~D[2027-01-01], revenue: 1_000, orders: 2},
      %{date: ~D[2026-11-02], revenue: 3_000, orders: 1},
      %{date: ~D[2026-10-30], revenue: 6_000, orders: 2},
      %{date: ~D[2026-12-31], revenue: 2_000, orders: 1},
      %{date: ~D[2026-11-01], revenue: -1_000, orders: 1}
    ]

    assert [october, november, new_year] =
             DelivestWeb.Staff.StatisticsLive.SalesChart.buckets(daily, "week")

    assert {october.from, october.to, october.revenue, october.orders, october.avg_check} ==
             {~D[2026-10-30], ~D[2026-11-01], 5_000, 3, 1_667}

    assert {november.from, november.to} == {~D[2026-11-02], ~D[2026-11-02]}

    assert {new_year.from, new_year.to, new_year.avg_check} ==
             {~D[2026-12-31], ~D[2027-01-01], 1_000}
  end

  test "the crm split shows only for a branch on a crm", %{conn: conn} do
    {conn, branch} = login(conn, ["statistics.read"])

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/statistics?period=today")
    refute has_element?(lv, "#statistics-transfer-destination")

    Delivest.Repo.insert!(%Delivest.Identity.Branch.BranchInfo{
      branch_id: branch.id,
      crm: %{enabled: true, provider: :iiko}
    })

    Cachex.del(:branch_cache, branch.id)

    branch.id |> order_fixture() |> completed()
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/statistics?tab=sales&period=today")
    assert has_element?(lv, "#statistics-transfer-destination")
  end

  test "overview defers details and completed orders open a scoped drilldown", %{conn: conn} do
    {conn, branch} = login(conn, ["statistics.read", "orders.read"])
    order = branch.id |> order_fixture(price: 12_000) |> completed()

    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/statistics?tab=overview&period=today")
    assigns = :sys.get_state(view.pid).socket.assigns
    refute Map.has_key?(assigns, :products)
    refute Map.has_key?(assigns, :by_fulfillment)
    assert has_element?(view, "#statistics-orders-link[href*='tab=orders']")

    render_patch(view, ~p"/staff/b/#{branch}/statistics?tab=orders&period=today")
    assert has_element?(view, "#statistics-order-#{order.id}")
    assert has_element?(view, "#statistics-order-rows a[href*='/orders/#{order.id}']")

    assert has_element?(
             view,
             "#statistics-order-details a[href*='period=today']",
             "Back to statistics"
           )
  end

  test "order drilldown stays hidden without order read permission", %{conn: conn} do
    {conn, branch} = login(conn, ["statistics.read"])
    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/statistics?tab=overview&period=today")
    refute has_element?(view, "#statistics-orders-link")
    refute has_element?(view, "#statistics-cancelled-link")
    refute has_element?(view, "#statistics-refunds-link")

    render_patch(view, ~p"/staff/b/#{branch}/statistics?tab=orders&period=today")
    assert has_element?(view, "#statistics-sales-detail")
    refute has_element?(view, "#statistics-order-details")
  end

  test "open sales and channel report react to branch visibility changes without changing revenue",
       %{conn: conn} do
    {conn, branch} = login(conn, ["statistics.read", "integrations.update"])
    staff = Delivest.Repo.get!(Delivest.Identity.Staff, Plug.Conn.get_session(conn, "staff_id"))
    staff = Delivest.Repo.preload(staff, :role)

    assert {:ok, branch} =
             Delivest.Identity.Branches.update_integrations(staff, branch, %{
               "channels" => %{"yandex_eda" => %{"enabled" => true}}
             })

    order = branch.id |> order_fixture(price: 12_000) |> completed()
    Delivest.Repo.update!(Ecto.Changeset.change(order, source: "yandex_eda"))

    assert {:ok, _} =
             Delivest.Features.configure("analytics_extended", :franchise, true, actor: "test")

    assert {:ok, _} =
             Delivest.Features.configure("analytics_extended", {:branch, branch.id}, true,
               actor: "test"
             )

    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/statistics?tab=sales&period=today")
    assert has_element?(view, "#statistics-order-source", "Яндекс Еда")
    revenue = :sys.get_state(view.pid).socket.assigns.overview.summary.revenue
    assert revenue == 12_000

    assert {:ok, _} =
             Delivest.Identity.Branches.update_integrations(staff, branch, %{
               "channels" => %{"yandex_eda" => %{"enabled" => false}}
             })

    assert has_element?(view, "#statistics-order-source", "Other")
    refute has_element?(view, "#statistics-order-source", "Яндекс Еда")
    assert :sys.get_state(view.pid).socket.assigns.overview.summary.revenue == revenue

    render_patch(view, ~p"/staff/b/#{branch}/analytics/channels?period=today")
    refute has_element?(view, ~s{select[name="channel"] option[value="yandex_eda"]})
  end

  test "custom period comes from the filter form", %{conn: conn} do
    {conn, branch} = login(conn, ["statistics.read"])
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/statistics?tab=overview")

    lv
    |> form("#statistics-filter", %{"period" => "custom"})
    |> render_change()

    today = Delivest.LocalTime.today()
    from = Date.to_iso8601(today)
    to = Date.to_iso8601(today)

    query = %{
      "from" => from,
      "period" => "custom",
      "sort" => "revenue",
      "tab" => "overview",
      "to" => to
    }

    assert_patch(lv, ~p"/staff/b/#{branch}/statistics?#{query}")
    assert has_element?(lv, ~s{input[name="from"][value="#{from}"]})
  end

  test "available chart steps follow the selected period", %{conn: conn} do
    {conn, branch} = login(conn, ["statistics.read"])

    {:ok, short, _} =
      live(
        conn,
        ~p"/staff/b/#{branch}/statistics?period=custom&from=2026-11-10&to=2026-11-16&granularity=month"
      )

    assert :sys.get_state(short.pid).socket.assigns.granularity == "day"
    refute has_element?(short, "#statistics-chart-step-form")

    {:ok, middle, _} =
      live(conn, ~p"/staff/b/#{branch}/statistics?period=custom&from=2026-11-10&to=2026-11-23")

    assert has_element?(middle, "#statistics-granularity option[value=day][selected]")
    assert has_element?(middle, "#statistics-granularity option[value=week]")
    refute has_element?(middle, "#statistics-granularity option[value=month]")

    {:ok, long, _} =
      live(conn, ~p"/staff/b/#{branch}/statistics?period=custom&from=2026-08-01&to=2026-09-30")

    assert has_element?(long, "#statistics-granularity option[value=week][selected]")
    assert has_element?(long, "#statistics-granularity option[value=month]")

    {:ok, longest, _} =
      live(conn, ~p"/staff/b/#{branch}/statistics?period=custom&from=2026-01-01&to=2026-04-30")

    assert has_element?(longest, "#statistics-granularity option[value=month][selected]")
  end

  test "branch chart step preserves custom comparison and resets on period change", %{conn: conn} do
    {conn, branch} = login(conn, ["statistics.read"])

    {:ok, view, _} =
      live(
        conn,
        ~p"/staff/b/#{branch}/statistics?period=custom&from=2026-11-10&to=2026-11-23&compare=custom&compare_from=2026-10-10&compare_to=2026-10-23"
      )

    assert has_element?(view, "#statistics-sales-detail")
    assert has_element?(view, "#statistics-granularity option[value=day][selected]")

    view
    |> form("#statistics-chart-step-form", %{"granularity" => "week"})
    |> render_change()

    query = %{
      "compare" => "custom",
      "compare_from" => "2026-10-10",
      "compare_to" => "2026-10-23",
      "from" => "2026-11-10",
      "granularity" => "week",
      "period" => "custom",
      "sort" => "revenue",
      "tab" => "sales",
      "to" => "2026-11-23"
    }

    assert_patch(view, ~p"/staff/b/#{branch}/statistics?#{query}")

    assert has_element?(view, "#statistics-granularity option[value=week][selected]")
    assert has_element?(view, ~s{input[name="from"][value="2026-11-10"]})
    assert has_element?(view, ~s{input[name="to"][value="2026-11-23"]})
    assert has_element?(view, "#statistics-chart-revenue [data-series=selected]")

    view |> form("#statistics-filter", %{"period" => "today"}) |> render_change()

    reset_query = %{
      "compare" => "custom",
      "compare_from" => "2026-10-10",
      "compare_to" => "2026-10-23",
      "period" => "today",
      "sort" => "revenue",
      "tab" => "sales"
    }

    assert_patch(view, ~p"/staff/b/#{branch}/statistics?#{reset_query}")

    refute has_element?(view, "#statistics-chart-step-form")
  end

  test "invalid custom period shows an error and can be corrected", %{conn: conn} do
    {conn, branch} = login(conn, ["statistics.read"])

    {:ok, lv, _html} =
      live(
        conn,
        ~p"/staff/b/#{branch}/statistics?tab=overview&period=custom&from=bad&to=2026-01-01"
      )

    assert has_element?(lv, "#statistics-period-error[role=alert]")
    assert has_element?(lv, ~s{input[name="from"][value=""]})
    refute has_element?(lv, "#statistics-overview")
    refute has_element?(lv, "#statistics-overview")

    lv
    |> form("#statistics-filter", %{
      "period" => "custom",
      "from" => "2026-01-02",
      "to" => "2026-01-01"
    })
    |> render_change()

    refute has_element?(lv, "#statistics-period-error")
    assert has_element?(lv, "#statistics-overview")
    assert has_element?(lv, ~s{input[name="from"][value="2026-01-02"]})
  end

  test "nested custom date params are rejected without rendering them", %{conn: conn} do
    {conn, branch} = login(conn, ["statistics.read"])
    path = ~p"/staff/b/#{branch}/statistics"

    {:ok, lv, _html} =
      live(
        conn,
        path <> "?period=custom&from[x]=2026-01-01&to[]=2026-01-02"
      )

    assert has_element?(lv, "#statistics-period-error")
    assert has_element?(lv, ~s{input[name="from"][value=""]})
    assert has_element?(lv, ~s{input[name="to"][value=""]})
    refute has_element?(lv, "#statistics-overview")

    render_patch(lv, path <> "?tab=products&period=custom&from[x]=2026-01-01&to[]=2026-01-02")
    assert has_element?(lv, "#statistics-period-error")
  end

  test "oversized custom period hides all report tabs", %{conn: conn} do
    {conn, branch} = login(conn, ["statistics.read"])

    {:ok, lv, _html} =
      live(
        conn,
        ~p"/staff/b/#{branch}/statistics?tab=products&period=custom&from=2024-01-01&to=2025-01-01"
      )

    assert has_element?(lv, "#statistics-period-error")
    refute has_element?(lv, "h2", "Products sold")
  end

  test "requires the statistics.read permission", %{conn: conn} do
    {conn, branch} = login(conn, ["orders.read"])
    dashboard = ~p"/staff/b/#{branch}/dashboard"

    assert {:error, {:redirect, %{to: ^dashboard}}} =
             live(conn, ~p"/staff/b/#{branch}/statistics")
  end

  test "comparison opens explicit date controls and applies a preceding equal period", %{
    conn: conn
  } do
    {conn, branch} = login(conn, ["statistics.read"])

    {:ok, view, _} =
      live(conn, ~p"/staff/b/#{branch}/statistics?period=custom&from=2026-11-10&to=2026-11-16")

    refute has_element?(view, "input[name=compare][type=checkbox]")
    refute has_element?(view, "#statistics-comparison-controls")
    view |> element("#statistics-compare") |> render_click()
    view |> form("#statistics-comparison-form", %{"compare" => "previous"}) |> render_submit()
    assert has_element?(view, "#statistics-comparison-periods", "10.11.2026 — 16.11.2026")
    assert has_element?(view, "#statistics-comparison-periods", "03.11.2026 — 09.11.2026")
    view |> element("#statistics-close-comparison") |> render_click()
    refute has_element?(view, "#statistics-comparison-controls")
  end

  test "year and custom comparison links reload with explicit resolved dates", %{conn: conn} do
    {conn, branch} = login(conn, ["statistics.read"])

    {:ok, view, _} =
      live(
        conn,
        ~p"/staff/b/#{branch}/statistics?period=custom&from=2024-02-29&to=2024-02-29&compare=year"
      )

    assert has_element?(view, "#statistics-comparison-periods", "28.02.2023")

    render_patch(
      view,
      ~p"/staff/b/#{branch}/statistics?period=custom&from=2026-11-10&to=2026-11-16&compare=custom&compare_from=2026-10-01&compare_to=2026-10-07"
    )

    assert has_element?(view, "#statistics-comparison-periods", "01.10.2026 — 07.10.2026")

    render_patch(
      view,
      ~p"/staff/b/#{branch}/statistics?tab=sales&period=custom&from=2026-11-10&to=2026-11-16&compare=custom&compare_from=2026-10-01&compare_to=2026-10-07"
    )

    assert has_element?(view, "#statistics-top-products a[href*='compare_from=2026-10-01']")
  end

  test "invalid comparison dates are rejected while the selected summary remains available", %{
    conn: conn
  } do
    {conn, branch} = login(conn, ["statistics.read"])

    for comparison <- [
          "compare=custom&compare_from=bad&compare_to=2026-11-01",
          "compare=custom&compare_from[x]=bad&compare_to=2026-11-01",
          "compare=custom&compare_from=2024-01-01&compare_to=2026-01-01"
        ] do
      {:ok, view, _} =
        live(conn, "/staff/b/#{branch.slug}/statistics?tab=overview&period=today&" <> comparison)

      assert has_element?(view, "#statistics-comparison-error")
      refute has_element?(view, "#statistics-comparison-periods")
      assert has_element?(view, "#statistics-overview")
    end
  end

  test "old comparison links and scope transitions preserve comparison selection", %{conn: conn} do
    {conn, branch} = login(conn, ["statistics.read"])
    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/statistics?period=today&compare=true")
    assert has_element?(view, "#statistics-comparison-periods")

    assert {:ok, %{path: path}} =
             DelivestWeb.StaffBranchPath.transition(
               "/staff/b/#{branch.slug}/statistics?period=custom&from=2026-11-01&to=2026-11-07&compare=custom&compare_from=2026-10-01&compare_to=2026-10-07",
               :network
             )

    query = URI.decode_query(URI.parse(path).query)
    assert query["compare"] == "custom"
    assert query["compare_from"] == "2026-10-01"
    assert query["compare_to"] == "2026-10-07"
  end

  test "network sales includes only authorized branches without optional feature gates", %{
    conn: conn
  } do
    {conn, first} = login(conn, ["statistics.read", "statistics.network"])
    second = insert(:branch)
    other = insert(:branch)
    staff_id = Plug.Conn.get_session(conn, "staff_id")

    insert(:staff_branch,
      staff: Delivest.Repo.get!(Delivest.Identity.Staff, staff_id),
      branch: second
    )

    first.id |> order_fixture(price: 10_000) |> completed()
    second.id |> order_fixture(price: 20_000) |> completed()
    other.id |> order_fixture(price: 90_000) |> completed()

    {:ok, view, _} = live(conn, ~p"/staff/statistics?tab=overview&period=today")

    assert has_element?(view, "#statistics-overview-branches")
    refute has_element?(view, "#statistics-network-branch")
    assert :sys.get_state(view.pid).socket.assigns.overview.summary.revenue == 30_000

    assert {:error, {:redirect, %{to: selected_path}}} =
             live(conn, ~p"/staff/statistics?period=today&branch_id=#{second.id}")

    assert selected_path == "/staff/b/#{second.slug}/statistics?period=today"

    {:ok, selected, _} = live(conn, selected_path)
    assert :sys.get_state(selected.pid).socket.assigns.overview.summary.revenue == 20_000

    assert {:error, {:redirect, %{to: safe_path}}} =
             live(conn, ~p"/staff/statistics?period=today&branch_id=#{other.id}")

    assert safe_path == "/staff/statistics?period=today"

    render_patch(
      view,
      ~p"/staff/statistics?period=today&branch_ids[]=#{first.id}&branch_ids[]=#{other.id}"
    )

    assert :sys.get_state(view.pid).socket.assigns.overview.summary.revenue == 30_000
    render_patch(view, ~p"/staff/statistics?period=today&branch_ids=invalid")
    assert :sys.get_state(view.pid).socket.assigns.overview.summary.revenue == 30_000

    for query <- ["branch_ids[x]=invalid"] do
      render_patch(view, "/staff/statistics?period=today&" <> query)
      assert :sys.get_state(view.pid).socket.assigns.overview.summary.revenue == 30_000
    end

    for query <- ["branch_id[]=invalid", "branch_id[x]=invalid"] do
      assert {:error, {:redirect, %{to: "/staff/statistics?period=today"}}} =
               live(conn, "/staff/statistics?period=today&" <> query)
    end

    render_patch(view, ~p"/staff/statistics?period=today")
    assert :sys.get_state(view.pid).socket.assigns.overview.summary.revenue == 30_000
  end

  test "branch report URLs cannot grant access to an unassigned branch", %{conn: conn} do
    {conn, _branch} = login(conn, ["statistics.read"])
    other = insert(:branch)
    assert {:error, {:redirect, _}} = live(conn, ~p"/staff/b/#{other}/analytics/channels")
  end

  test "current sales tabs refresh automatically and partial historical data retries a bounded number of times",
       %{
         conn: conn
       } do
    {conn, branch} = login(conn, ["statistics.read"])
    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/statistics?period=today")

    for tab <- ~w(sales products categories) do
      render_patch(view, "/staff/b/#{branch.slug}/statistics?tab=#{tab}&period=today")
      state = :sys.get_state(view.pid)
      timer = state.socket.assigns.refresh_timer
      assert is_reference(timer)
      assert Process.read_timer(timer) in 1..30_000
    end

    timer = :sys.get_state(view.pid).socket.assigns.refresh_timer

    render_patch(
      view,
      ~p"/staff/b/#{branch}/statistics?period=custom&from=2026-01-01&to=2026-01-07"
    )

    assert is_reference(:sys.get_state(view.pid).socket.assigns.refresh_timer)
    assert Process.read_timer(timer) == false
  end

  test "automatic sales refresh preserves comparison date drafts", %{conn: conn} do
    {conn, branch} = login(conn, ["statistics.read"])
    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/statistics?period=today")
    view |> element("#statistics-compare") |> render_click()
    view |> form("#statistics-comparison-form", %{"compare" => "custom"}) |> render_change()

    view
    |> form("#statistics-comparison-form", %{
      "compare" => "custom",
      "compare_from" => "2026-10-01",
      "compare_to" => "2026-10-07"
    })
    |> render_change()

    state = :sys.get_state(view.pid)
    timer = state.socket.assigns.refresh_timer
    send(view.pid, {:refresh_report, state.socket.assigns.refresh_epoch})
    refreshed = :sys.get_state(view.pid)
    assert refreshed.socket.assigns.refresh_timer != timer

    assert has_element?(
             view,
             "#statistics-comparison-form input[name=compare_from][value='2026-10-01']"
           )

    assert has_element?(
             view,
             "#statistics-comparison-form input[name=compare_to][value='2026-10-07']"
           )

    refute has_element?(view, "#statistics-comparison-periods")
  end

  test "an expired refresh epoch performs no read" do
    socket = %Phoenix.LiveView.Socket{assigns: %{refresh_epoch: 2, tab: "sales"}}

    assert {:noreply, ^socket} =
             DelivestWeb.Staff.StatisticsLive.Index.handle_info({:refresh_report, 1}, socket)
  end

  test "global statistics ignores old branch kitchen timers and notifications", %{conn: conn} do
    {conn, branch} = login(conn, ["admin"])

    assert {:ok, _} =
             Delivest.Features.configure("analytics_franchise", :franchise, true, actor: "host")

    {:ok, view, _} = live(conn, ~p"/staff/statistics?tab=overview&period=today")
    send(view.pid, :kitchen_tick)
    send(view.pid, {:branch_orders_changed, branch.id})
    send(view.pid, {:kitchen_presence, branch.id})
    send(view.pid, {:kitchen_order_ready, %{branch_id: branch.id, id: Ecto.UUID.generate()}})
    state = :sys.get_state(view.pid)
    assert state.socket.assigns.current_branch == nil
    assert state.socket.assigns.new_orders_count == 0
    assert state.socket.assigns.kitchen_status == nil
    assert state.socket.assigns.kitchen_late_orders == []
    refute Map.has_key?(state.socket.assigns.flash, "info")
    assert has_element?(view, "#statistics-overview")
    assert has_element?(view, "#statistics-overview-sales-plot[data-chart]")
    assert has_element?(view, "#statistics-delivery-quality-chart[data-chart]")
    assert has_element?(view, "#statistics-delivery-quality-data")
    view |> element("#statistics-delivery-quality-data tbody button") |> render_click()
    assert has_element?(view, "#statistics-delivery-quality-detail")
    view |> element("#statistics-delivery-quality-detail button") |> render_click()
    refute has_element?(view, "#statistics-delivery-quality-detail")

    assert render_click(view, "overdue_confirm", %{"id" => Ecto.UUID.generate()}) =~
             "Permission denied"

    assert has_element?(view, "#statistics-overview")
  end

  test "automatic refresh advances relative periods after local midnight without resetting drafts",
       %{conn: conn} do
    {conn, branch} = login(conn, ["statistics.read"])
    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/statistics?period=today&compare=previous")
    {today, today} = Delivest.Analytics.resolve_period("today", nil, nil, branch.id)
    yesterday = Date.add(today, -1)

    :sys.replace_state(view.pid, fn state ->
      socket =
        Phoenix.Component.assign(state.socket,
          period: {yesterday, yesterday},
          comparison_draft: "custom",
          comparison_draft_from: "2026-10-01",
          comparison_draft_to: "2026-10-07"
        )

      %{state | socket: socket}
    end)

    epoch = :sys.get_state(view.pid).socket.assigns.refresh_epoch
    send(view.pid, {:refresh_report, epoch})
    assigns = :sys.get_state(view.pid).socket.assigns
    assert assigns.period == {today, today}
    assert assigns.comparison_period == {yesterday, yesterday}
    assert assigns.comparison_draft == "custom"
    assert assigns.comparison_draft_from == "2026-10-01"
    assert assigns.comparison_draft_to == "2026-10-07"
  end
end
