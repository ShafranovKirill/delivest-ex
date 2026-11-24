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

  test "VK pixel integration uses the selected branch route" do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["integrations.read"]))
    entry = DelivestWeb.StaffNav.integration_entry(:vk_ads, staff, branch)

    assert entry.label == "VK Реклама / Top.Mail.Ru"
    assert entry.path == "/staff/b/#{branch.slug}/integrations/vk-ads"
    assert entry.scope == :branch
    assert DelivestWeb.StaffNav.integration_entry(:vk_ads, staff, nil).path == nil
  end

  test "analytics navigation has one statistics entry and limits network access" do
    branch = insert(:branch)

    for permissions <- [
          ["statistics.read"],
          ["statistics.network"],
          ["statistics.read", "statistics.network"]
        ] do
      staff = insert(:staff, role: insert(:role, permissions: permissions))
      insert(:staff_branch, staff: staff, branch: branch)
      staff = Repo.preload(staff, [:role, :branches])
      pages = DelivestWeb.StaffNav.pages(staff, branch)

      assert Enum.count(pages, &(&1.id == :statistics)) ==
               if("statistics.read" in permissions, do: 1, else: 0)

      refute Enum.any?(pages, &(&1.id == :network_sales))

      if length(permissions) == 2 do
        assert Enum.find(pages, &(&1.id == :statistics)).path ==
                 "/staff/b/#{branch.slug}/statistics"

        global = DelivestWeb.StaffNav.pages(staff, nil)
        assert Enum.count(global, &(&1.path == "/staff/statistics")) == 1
      end
    end
  end

  test "analytics sidebar shows reachable acquisition and buyers for the branch" do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["statistics.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    staff = Repo.preload(staff, [:role, :branches])

    assert {:ok, _} = Features.configure("analytics_funnel", :franchise, true, actor: "test")

    assert {:ok, _} =
             Features.configure("analytics_funnel", {:branch, branch.id}, true, actor: "test")

    assert {:ok, _} = Features.configure("analytics_extended", :franchise, true, actor: "test")

    assert {:ok, _} =
             Features.configure("analytics_extended", {:branch, branch.id}, true, actor: "test")

    entries = analytics_entries(staff, branch)

    assert Enum.map(entries, & &1.id) == [
             :statistics,
             :analytics_acquisition,
             :analytics_customers
           ]

    assert Enum.at(entries, 0).label == "Sales"
    assert Enum.at(entries, 1).path == "/staff/b/#{branch.slug}/analytics/funnel"
    assert Enum.at(entries, 2).path == "/staff/b/#{branch.slug}/analytics/customers"

    assert {:ok, _} = Features.configure("analytics_links", :franchise, true, actor: "test")

    assert {:ok, _} =
             Features.configure("analytics_links", {:branch, branch.id}, true, actor: "test")

    assert Enum.at(analytics_entries(staff, branch), 1).path ==
             "/staff/b/#{branch.slug}/analytics/sources"

    assert {:ok, _} =
             Features.configure("analytics_links", {:branch, branch.id}, false, actor: "test")

    assert Enum.at(analytics_entries(staff, branch), 1).path ==
             "/staff/b/#{branch.slug}/analytics/funnel"

    assert {:ok, _} =
             Features.configure("analytics_extended", {:branch, branch.id}, false, actor: "test")

    assert Enum.map(analytics_entries(staff, branch), & &1.id) ==
             [:statistics, :analytics_acquisition]
  end

  test "network analytics uses only allowed branches and network permission" do
    allowed = insert(:branch)
    other = insert(:branch)

    assert {:ok, _} = Features.configure("analytics_links", :franchise, true, actor: "test")

    assert {:ok, _} =
             Features.configure("analytics_links", {:branch, other.id}, true, actor: "test")

    staff =
      insert(:staff, role: insert(:role, permissions: ~w(statistics.read statistics.network)))

    insert(:staff_branch, staff: staff, branch: allowed)
    staff = Repo.preload(staff, [:role, :branches])

    assert Enum.map(analytics_entries(staff, nil), & &1.id) == [:statistics]

    assert {:ok, _} = Features.configure("yandex_ads", :franchise, true, actor: "test")
    assert {:ok, _} = Features.configure("yandex_costs", :franchise, true, actor: "test")
    assert Enum.at(analytics_entries(staff, nil), 1).path == "/staff/analytics/advertising"

    assert {:ok, _} =
             Features.configure("analytics_links", {:branch, allowed.id}, true, actor: "test")

    assert Enum.at(analytics_entries(staff, nil), 1).path == "/staff/analytics/sources"

    assert {:ok, _} = Features.configure("analytics_extended", :franchise, true, actor: "test")

    assert {:ok, _} =
             Features.configure("analytics_extended", {:branch, allowed.id}, true, actor: "test")

    assert Enum.at(analytics_entries(staff, nil), 2).path == "/staff/analytics/customers"

    limited = insert(:staff, role: insert(:role, permissions: ["statistics.read"]))
    insert(:staff_branch, staff: limited, branch: allowed)
    limited = Repo.preload(limited, [:role, :branches])
    assert analytics_entries(limited, nil) == []
  end

  defp analytics_entries(staff, branch) do
    DelivestWeb.StaffNav.entries(staff, branch)
    |> Enum.flat_map(& &1.entries)
    |> Enum.find(&(&1.id == :analytics))
    |> then(fn group -> if group, do: group.items, else: [] end)
  end

  test "advertising feature link requires both statistics permissions" do
    network_only =
      insert(:staff, role: insert(:role, permissions: ["statistics.network"]))
      |> Repo.preload([:role, :branches])

    authorized =
      insert(:staff,
        role: insert(:role, permissions: ["statistics.read", "statistics.network"])
      )
      |> Repo.preload([:role, :branches])

    assert DelivestWeb.StaffNav.feature_entry("yandex_costs", network_only).path == nil

    assert DelivestWeb.StaffNav.feature_entry("yandex_costs", authorized).path ==
             "/staff/analytics/advertising"
  end

  test "global statistics renders franchise report without an active branch", %{conn: conn} do
    branch = insert(:branch)
    conn = login(conn, ["statistics.read", "statistics.network"], [branch])

    {:ok, view, _} = live(conn, ~p"/staff/statistics?period=today")

    assert has_element?(view, "#statistics-sales-detail")

    assert has_element?(view, "#header-branch")
    refute has_element?(view, "#statistics-scope")
  end

  test "limited statistics role opens its branch and cannot open the network summary", %{
    conn: conn
  } do
    branch = insert(:branch)
    conn = login(conn, ["statistics.read"], [branch])
    assert {:error, {:redirect, _}} = live(conn, ~p"/staff/statistics")
    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/statistics")
    assert has_element?(view, "#statistics-sales-detail")
    assert has_element?(view, "#header-branch-static")
    refute has_element?(view, "#statistics-scope")
    refute has_element?(view, "#sidebar-section-nav-analytics_comparison")
  end

  test "header statistics transitions preserve compatible filters but drop another branch link",
       %{conn: conn} do
    first = insert(:branch)
    second = insert(:branch)
    conn = login(conn, ["statistics.read"], [first, second], first.id)
    {:ok, _} = Features.configure("analytics_links", :franchise, true, actor: "test")
    {:ok, _} = Features.configure("analytics_links", {:branch, first.id}, true, actor: "test")

    {:ok, view, _} =
      live(
        conn,
        ~p"/staff/b/#{first}/analytics/sources?period=custom&from=2026-11-01&to=2026-11-07&link_id=123"
      )

    assert has_element?(view, "#header-branch")
    refute has_element?(view, "#statistics-scope")

    assert {:ok, %{path: path}} =
             DelivestWeb.StaffBranchPath.transition(
               "/staff/b/#{first.slug}/analytics/sources?period=custom&from=2026-11-01&to=2026-11-07&link_id=123",
               {:branch, second.slug}
             )

    assert URI.parse(path).path == "/staff/b/#{second.slug}/analytics/sources"
    query = URI.decode_query(URI.parse(path).query)
    assert query["from"] == "2026-11-01" and query["to"] == "2026-11-07"
    refute query["link_id"]
  end

  test "analytics sidebar keeps section active and carries the selected period", %{conn: conn} do
    branch = insert(:branch)
    conn = login(conn, ~w(statistics.read statistics.network), [branch], branch.id)

    assert {:ok, _} = Features.configure("analytics_links", :franchise, true, actor: "test")

    assert {:ok, _} =
             Features.configure("analytics_links", {:branch, branch.id}, true, actor: "test")

    assert {:ok, _} = Features.configure("analytics_extended", :franchise, true, actor: "test")

    assert {:ok, _} =
             Features.configure("analytics_extended", {:branch, branch.id}, true, actor: "test")

    period = "period=custom&from=2026-11-01&to=2026-11-07"
    {:ok, sources, _} = live(conn, "/staff/b/#{branch.slug}/analytics/sources?#{period}")

    assert has_element?(sources, "#sidebar-group-analytics[open]")

    assert has_element?(
             sources,
             "#sidebar-section-nav-analytics_acquisition[aria-current='page'][href^='/staff/b/#{branch.slug}/analytics/sources?']"
           )

    assert has_element?(
             sources,
             "#sidebar-section-nav-analytics_customers[href^='/staff/b/#{branch.slug}/analytics/customers?']"
           )

    assert_sidebar_period(sources, "#sidebar-section-nav-analytics_customers")

    {:ok, channels, _} = live(conn, "/staff/analytics/channels?#{period}")

    assert has_element?(
             channels,
             "#sidebar-section-nav-statistics[aria-current='page'][href^='/staff/statistics?']"
           )

    assert has_element?(
             channels,
             "#sidebar-section-nav-analytics_acquisition[href^='/staff/analytics/sources?']"
           )

    assert_sidebar_period(channels, "#sidebar-section-nav-analytics_acquisition")
  end

  defp assert_sidebar_period(view, selector) do
    assert [href] =
             view
             |> render()
             |> LazyHTML.from_fragment()
             |> LazyHTML.query(selector)
             |> LazyHTML.attribute("href")

    assert URI.decode_query(URI.parse(href).query) == %{
             "period" => "custom",
             "from" => "2026-11-01",
             "to" => "2026-11-07"
           }
  end

  test "analytics period links and scope transition preserve compatible filters" do
    source =
      "/staff/b/first/analytics/sources?period=custom&from=2026-11-01&to=2026-11-07&link_id=123"

    path =
      DelivestWeb.StaffBranchPath.contextual_navigation_path(
        "/staff/analytics/comparison",
        nil,
        source
      )

    assert URI.parse(path).path == "/staff/analytics/comparison"

    assert URI.decode_query(URI.parse(path).query) == %{
             "period" => "custom",
             "from" => "2026-11-01",
             "to" => "2026-11-07"
           }

    path =
      DelivestWeb.StaffBranchPath.contextual_navigation_path(
        "/staff/b/first/analytics/customers?channel=web",
        nil,
        source
      )

    assert URI.decode_query(URI.parse(path).query) == %{
             "period" => "custom",
             "from" => "2026-11-01",
             "to" => "2026-11-07",
             "channel" => "web"
           }

    assert {:ok, %{path: transitioned}} =
             DelivestWeb.StaffBranchPath.transition(
               "/staff/b/first/statistics?tab=sales&period=month&granularity=month",
               {:branch, "second"}
             )

    assert URI.parse(transitioned).path == "/staff/b/second/statistics"

    assert URI.decode_query(URI.parse(transitioned).query) == %{
             "tab" => "sales",
             "period" => "month",
             "granularity" => "month"
           }
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

    assert has_element?(clients, "#staff-section-navigation.tabs-box.rounded-none .tab-active")
    assert has_element?(clients, "#sidebar-staff-section-navigation .menu-active")

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

    assert has_element?(settings, "#sidebar-group-settings[open]")
    assert has_element?(settings, "#sidebar-settings-nav-features[aria-current='page']")

    assert has_element?(
             settings,
             "#sidebar-settings-nav-data_system"
           )

    refute has_element?(settings, "#sidebar-group-data-system")

    refute has_element?(
             settings,
             "#nav-section-main > ul:not(#nav-section-settings) a[href='/staff/branches']"
           )

    refute has_element?(
             settings,
             "#nav-section-main > ul:not(#nav-section-settings) a[href='/staff/integrations']"
           )

    refute has_element?(
             settings,
             "#nav-section-main > ul:not(#nav-section-settings) a[href='/staff/b/#{branch.slug}/delivery']"
           )

    {:ok, delivery, _} = live(conn, ~p"/staff/b/#{branch}/delivery")

    assert has_element?(
             delivery,
             "#sidebar-group-settings[open] #sidebar-settings-nav-branches[aria-current='page']"
           )

    refute has_element?(delivery, "#sidebar-settings-nav-delivery_settings")
    assert has_element?(delivery, "#settings-nav-branches[aria-current='page']")
    refute has_element?(delivery, "#settings-nav-delivery_settings")

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

  test "employees follow finance and respect staff and roles permissions", %{conn: conn} do
    branch = insert(:branch)
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))

    main =
      DelivestWeb.StaffNav.entries(admin, branch)
      |> Enum.find(&(&1.id == :main))
      |> Map.fetch!(:entries)
      |> Enum.map(& &1.id)

    assert Enum.find_index(main, &(&1 == :employees)) ==
             Enum.find_index(main, &(&1 == :finance)) + 1

    {:ok, staff_view, _} = live(login(conn, ["staff.read"], []), ~p"/staff/employee")
    assert has_element?(staff_view, "#sidebar-group-employees[open]")
    assert has_element?(staff_view, "#sidebar-group-employees #sidebar-section-nav-employee")
    refute has_element?(staff_view, "#sidebar-group-employees #sidebar-section-nav-roles")
    refute has_element?(staff_view, "#sidebar-group-settings")

    {:ok, roles_view, _} = live(login(conn, ["roles.read"], []), ~p"/staff/roles")
    assert has_element?(roles_view, "#sidebar-group-employees[open]")
    assert has_element?(roles_view, "#sidebar-group-employees #sidebar-section-nav-roles")
    refute has_element?(roles_view, "#sidebar-group-employees #sidebar-section-nav-employee")
    refute has_element?(roles_view, "#sidebar-group-settings")
  end

  test "data and system landing offers five permitted actions and keeps transfer scope", %{
    conn: conn
  } do
    branch = insert(:branch)
    admin_conn = login(conn, ["admin"], [branch], branch.id)
    {:ok, scoped_settings, _} = live(admin_conn, "/staff/settings?branch=#{branch.slug}")

    assert has_element?(
             scoped_settings,
             "#settings-nav-data_system[href='/staff/settings/data-system?branch=#{branch.slug}']"
           )

    refute has_element?(scoped_settings, "#group-data-system")
    refute has_element?(scoped_settings, "#sidebar-group-data-system")

    {:ok, admin, _} = live(admin_conn, "/staff/settings/data-system?branch=#{branch.slug}")
    assert has_element?(admin, "#sidebar-settings-nav-data_system[aria-current='page']")
    assert has_element?(admin, "#settings-nav-data_system[aria-current='page']")
    assert has_element?(admin, "#settings-navigation.tabs-box.rounded-none .tab-active")
    assert has_element?(admin, "#data-system-content #audit-events")
    assert has_element?(admin, "#data-system-action-events[aria-current='page']")

    assert ["data-system-action-events" | _] =
             admin
             |> render()
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#data-system-navigation > a")
             |> LazyHTML.attribute("id")

    for {id, path} <- [
          {"data_transfer", "/staff/settings/data-transfer?branch=#{branch.slug}"},
          {"metrics", "/staff/diagnostics"},
          {"events", "/staff/settings/data-system?branch=#{branch.slug}"},
          {"raw", "/staff/logs/raw"},
          {"errors", "/staff/logs/errors"}
        ] do
      assert has_element?(
               admin,
               "main #data-system-navigation #data-system-action-#{id}[href='#{path}']"
             )
    end

    refute has_element?(admin, "#staff-context-navigation #data-system-navigation")
    refute has_element?(admin, "#main-sidebar #data-system-navigation")

    {:ok, transfer, _} = live(admin_conn, "/staff/settings/data-transfer?branch=#{branch.slug}")

    assert has_element?(
             transfer,
             "#data-transfer-branch[href='/staff/branches/#{branch.slug}/edit/snapshot']"
           )

    assert has_element?(transfer, "#data-transfer-franchise[href='/staff/franchise/snapshot']")
    assert has_element?(transfer, "main #data-system-action-data_transfer[aria-current='page']")

    {:ok, branch_snapshot, _} = live(admin_conn, "/staff/branches/#{branch.slug}/edit/snapshot")

    assert has_element?(
             branch_snapshot,
             "#settings-nav-data_system[href='/staff/settings/data-system?branch=#{branch.slug}'][aria-current='page']"
           )

    {:ok, franchise_snapshot, _} = live(admin_conn, "/staff/franchise/snapshot")

    assert has_element?(
             franchise_snapshot,
             "#settings-nav-data_system[href='/staff/settings/data-system'][aria-current='page']"
           )

    {:ok, network_transfer, _} = live(admin_conn, "/staff/settings/data-transfer")

    assert has_element?(
             network_transfer,
             "#data-transfer-branch[href^='/staff/branches/select?'][href*='return_to=%2Fstaff%2Fsettings%2Fdata-transfer']"
           )

    assert has_element?(network_transfer, "#data-transfer-franchise")

    branch_conn = login(conn, ["branches.read", "branches.update"], [branch], branch.id)
    transfer_path = "/staff/settings/data-transfer?branch=#{branch.slug}"

    assert {:error, {:redirect, %{to: ^transfer_path}}} =
             live(branch_conn, "/staff/settings/data-system?branch=#{branch.slug}")

    {:ok, branch_transfer, _} =
      live(branch_conn, "/staff/settings/data-transfer?branch=#{branch.slug}")

    assert has_element?(branch_transfer, "#data-transfer-branch")
    refute has_element?(branch_transfer, "#data-transfer-franchise")

    reader_conn = login(conn, ["branches.read"], [branch], branch.id)

    assert {:error, {:redirect, %{to: "/staff/dashboard"}}} =
             live(reader_conn, "/staff/settings/data-transfer")

    assert {:error, {:redirect, %{to: "/staff/dashboard"}}} =
             live(reader_conn, "/staff/settings/data-system")

    assert {:error, {:live_redirect, %{to: "/staff/settings/data-system"}}} =
             live(admin_conn, "/staff/settings/data-system?branch=missing")

    assert {:error, {:live_redirect, %{to: "/staff/settings/data-transfer"}}} =
             live(admin_conn, "/staff/settings/data-transfer?branch=missing")

    orphan_conn = login(conn, ["branches.read", "branches.update"], [])

    assert {:error, {:redirect, %{to: "/staff/dashboard"}}} =
             live(orphan_conn, "/staff/settings/data-transfer")

    assert {:error, {:redirect, %{to: "/staff/dashboard"}}} =
             live(orphan_conn, "/staff/settings/data-system")
  end

  test "branch switching preserves the data transfer landing", %{conn: conn} do
    branch = insert(:branch)
    second = insert(:branch)
    conn = login(conn, ["admin"], [branch, second], branch.id)
    {:ok, transfer, _} = live(conn, "/staff/settings/data-transfer?branch=#{branch.slug}")
    assert has_element?(transfer, "#header-branch")

    assert {:ok, %{path: selected_path}} =
             DelivestWeb.StaffBranchPath.transition(
               "/staff/settings/data-transfer?branch=#{branch.slug}",
               {:branch, second.slug}
             )

    assert selected_path == "/staff/settings/data-transfer?branch=#{second.slug}"

    assert {:ok, %{path: "/staff/settings/data-transfer"}} =
             DelivestWeb.StaffBranchPath.transition(
               "/staff/settings/data-transfer?branch=#{branch.slug}",
               :network
             )

    source = "/staff/branches/#{branch.slug}/edit/snapshot"

    assert {:ok, %{return_to: "/staff/settings/data-transfer"}} =
             DelivestWeb.StaffBranchPath.selection_intent(
               source,
               "/staff/settings/data-transfer"
             )

    assert {:ok, destination} =
             DelivestWeb.StaffBranchPath.selection_destination(source, second.slug)

    assert destination == "/staff/branches/#{second.slug}/edit/snapshot"
  end

  test "branch switching preserves the data and system landing", %{conn: conn} do
    branch = insert(:branch)
    second = insert(:branch)
    conn = login(conn, ["admin"], [branch, second], branch.id)
    {:ok, page, _} = live(conn, "/staff/settings/data-system?branch=#{branch.slug}")
    assert has_element?(page, "#header-branch")

    expected_path = "/staff/settings/data-system?branch=#{second.slug}"

    assert {:ok, %{path: ^expected_path}} =
             DelivestWeb.StaffBranchPath.transition(
               "/staff/settings/data-system?branch=#{branch.slug}",
               {:branch, second.slug}
             )

    assert {:ok, %{path: "/staff/settings/data-system"}} =
             DelivestWeb.StaffBranchPath.transition(
               "/staff/settings/data-system?branch=#{branch.slug}",
               :network
             )
  end

  test "data and system stays active on logs with actions in content", %{conn: conn} do
    conn = login(conn, ["logs.read"], [])
    {:ok, logs, _} = live(conn, ~p"/staff/logs")

    assert has_element?(
             logs,
             "#settings-nav-data_system[href='/staff/settings/data-system'][aria-current='page']"
           )

    assert has_element?(logs, "#sidebar-settings-nav-data_system[aria-current='page']")
    assert has_element?(logs, "main #data-system-action-events[aria-current='page']")
    refute has_element?(logs, "#data-system-action-data_transfer")
    refute has_element?(logs, "#sidebar-group-data-system")
    refute has_element?(logs, "#group-data-system")
  end

  test "product subpages keep Products active without duplicate sidebar links", %{conn: conn} do
    branch = insert(:branch)
    conn = login(conn, ["categories.read", "products.read"], [branch], branch.id)

    for path <- [~p"/staff/b/#{branch}/products/stops", ~p"/staff/b/#{branch}/menu/popular"] do
      {:ok, view, _} = live(conn, path)

      assert has_element?(view, "#nav-section-main")

      assert has_element?(view, "#nav-section-main a[href='/staff/b/#{branch.slug}/products']")
      active = if String.ends_with?(path, "/stops"), do: "stops", else: "collections"

      assert has_element?(
               view,
               "#sidebar-group-menu[open] #sidebar-product-section-tab-#{active}[aria-current='page']"
             )

      assert has_element?(view, "#sidebar-group-menu #sidebar-product-section-tab-stops")
      assert has_element?(view, "#sidebar-group-menu #sidebar-product-section-tab-collections")

      refute has_element?(
               view,
               "#nav-section-main > ul > li > a[href='/staff/b/#{branch.slug}/products/stops']"
             )

      refute has_element?(
               view,
               "#nav-section-main > ul > li > a[href='/staff/b/#{branch.slug}/menu/popular']"
             )

      assert has_element?(view, "#staff-section-navigation #product-section-tab-collections")
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
