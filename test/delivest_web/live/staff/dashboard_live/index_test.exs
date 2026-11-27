defmodule DelivestWeb.Staff.DashboardLive.IndexTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias DelivestWeb.Staff.DashboardLive.Index

  describe "hourly chart rows" do
    test "trims to active bounds and keeps internal zero hours" do
      today = [%{hour: 9, orders: 2, revenue: 1_000}, %{hour: 11, orders: 1, revenue: 500}]

      assert Index.hourly_rows(today, [], 12) == [
               %{hour: 9, orders: 2, yesterday_orders: 0, revenue: 1_000},
               %{hour: 10, orders: 0, yesterday_orders: 0, revenue: 0},
               %{hour: 11, orders: 1, yesterday_orders: 0, revenue: 500}
             ]
    end

    test "aligns today and yesterday by local hour" do
      today = [%{hour: 8, orders: 1, revenue: 300}]
      yesterday = [%{hour: 10, orders: 4, revenue: 1_200}]

      assert Index.hourly_rows(today, yesterday, 12) == [
               %{hour: 8, orders: 1, yesterday_orders: 0, revenue: 300},
               %{hour: 9, orders: 0, yesterday_orders: 0, revenue: 0},
               %{hour: 10, orders: 0, yesterday_orders: 4, revenue: 0}
             ]
    end

    test "keeps yesterday-only future hours and masks today's values" do
      today = [%{hour: 18, orders: 5, revenue: 2_000}]
      yesterday = [%{hour: 14, orders: 2, revenue: 900}]

      assert Index.hourly_rows(today, yesterday, 12) == [
               %{hour: 14, orders: nil, yesterday_orders: 2, revenue: nil}
             ]
    end

    test "returns no rows when neither day has orders" do
      today = [%{hour: 7, orders: 0, revenue: 0}]
      yesterday = [%{hour: 8, orders: 0, revenue: 0}]
      assert Index.hourly_rows(today, yesterday, 12) == []
    end
  end

  describe "dashboard page" do
    test "network and branch dashboards show compact empty hourly state without the historical heatmap",
         %{
           conn: conn
         } do
      branch = insert(:branch)

      staff =
        insert(:staff,
          role: insert(:role, permissions: ["statistics.read", "statistics.network"])
        )

      insert(:staff_branch, staff: staff, branch: branch)
      conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

      {:ok, network, _} = live(conn, ~p"/staff/dashboard")
      assert has_element?(network, "#dashboard-hourly-empty")
      refute has_element?(network, "#dashboard-orders-by-hour-plot")

      refute has_element?(network, "#dashboard-order-heatmap")
      refute has_element?(network, "#statistics-heatmap-chart")

      {:ok, local, _} = live(conn, ~p"/staff/b/#{branch}/dashboard")
      assert has_element?(local, "#dashboard-hourly-empty")
      refute has_element?(local, "#dashboard-orders-by-hour-plot")
      refute has_element?(local, "#dashboard-order-heatmap")
      refute has_element?(local, "#statistics-heatmap-chart")
    end

    test "hourly comparison remains visible when only yesterday has orders", %{conn: conn} do
      branch = insert(:branch)
      staff = insert(:staff, role: insert(:role, permissions: ["statistics.read"]))
      insert(:staff_branch, staff: staff, branch: branch)
      zone = Delivest.LocalTime.timezone(branch.id)
      yesterday = Date.add(Delivest.LocalTime.today(zone), -1)
      at = DateTime.new!(yesterday, ~T[12:00:00], zone) |> DateTime.shift_zone!("Etc/UTC")

      Delivest.OrderFixtures.order_fixture(branch.id)
      |> Ecto.Changeset.change(inserted_at: at)
      |> Delivest.Repo.update!()

      conn = init_test_session(conn, %{"staff_id" => staff.id})
      {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/dashboard")

      assert has_element?(view, "#dashboard-hourly-empty")
      assert has_element?(view, "#dashboard-orders-by-hour-plot[data-chart*='yesterday_orders']")
    end

    test "all-branch dashboard includes only accessible branches", %{conn: conn} do
      first = insert(:branch, name: "First")
      second = insert(:branch, name: "Second")
      foreign = insert(:branch, name: "Foreign")
      staff = insert(:staff, role: insert(:role, permissions: ["statistics.read", "orders.read"]))
      insert(:staff_branch, staff: staff, branch: first)
      insert(:staff_branch, staff: staff, branch: second)
      a = Delivest.OrderFixtures.order_fixture(first.id, price: 10_000)
      b = Delivest.OrderFixtures.order_fixture(second.id, price: 20_000)
      c = Delivest.OrderFixtures.order_fixture(foreign.id, price: 40_000)
      problem = Delivest.OrderFixtures.order_fixture(second.id, price: 5_000)

      problem
      |> Ecto.Changeset.change(
        crm: %Delivest.Oms.Order.CrmSync{provider: "frontpad", status: "failed"}
      )
      |> Delivest.Repo.update!()

      conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => first.id})

      {:ok, all, html} = live(conn, ~p"/staff/dashboard")
      assert has_element?(all, "#dashboard-orders-by-hour-plot[data-chart]")
      assert has_element?(all, "#dashboard-orders-by-hour-plot table")

      assert has_element?(
               all,
               "#dashboard-branch-#{first.id} a[href='/staff/b/#{first.slug}/dashboard']"
             )

      assert has_element?(all, "#dashboard-branch-#{second.id} a[href*='status=created']")
      refute has_element?(all, "#dashboard-branch-#{foreign.id}")
      assert has_element?(all, "#dashboard-order-#{a.id}")
      assert has_element?(all, "#dashboard-order-#{b.id}")
      refute has_element?(all, "#dashboard-order-#{c.id}")

      assert has_element?(
               all,
               ~s(#dashboard-order-#{b.id} a[href="/staff/b/#{second.slug}/orders/#{b.id}"])
             )

      assert html =~ "300 ₽"
      refute html =~ "700 ₽"
      assert has_element?(all, "#dashboard-problem-orders", "1")
      assert has_element?(all, "#dashboard-alert-problem a[href*='/staff/branches/select']")

      {:ok, branch_view, _} = live(conn, ~p"/staff/b/#{first}/dashboard")
      assert has_element?(branch_view, "#dashboard-order-#{a.id}")
      refute has_element?(branch_view, "#dashboard-order-#{b.id}")

      assert {:error, {:redirect, %{to: "/staff/branches/select"}}} =
               live(conn, ~p"/staff/b/#{foreign}/dashboard")

      Delivest.Repo.get_by!(Delivest.Identity.StaffBranch,
        staff_id: staff.id,
        branch_id: second.id
      )
      |> Delivest.Repo.delete!()

      Cachex.del(:staff_cache, staff.id)

      send(all.pid, :staff_updated)
      _ = :sys.get_state(all.pid)
      refute has_element?(all, "#dashboard-order-#{b.id}")
      assert has_element?(all, "#dashboard-order-#{a.id}")
    end

    test "all-branch top products merges a product below fifth place in each branch", %{
      conn: conn
    } do
      first = insert(:branch)
      second = insert(:branch)
      staff = insert(:staff, role: insert(:role, permissions: ["statistics.read"]))
      insert(:staff_branch, staff: staff, branch: first)
      insert(:staff_branch, staff: staff, branch: second)

      shared = insert_branch_product(first.id, name: "Shared", price: 900)

      {:ok, _} =
        Delivest.Relations.create_relation(
          Delivest.Repo,
          "Branch",
          second.id,
          "Product",
          shared.id
        )

      for branch <- [first, second] do
        for n <- 1..5 do
          product = insert_branch_product(branch.id, price: 1000, name: "Top #{n}")
          Delivest.OrderFixtures.order_fixture(branch.id, product: product)
        end

        Delivest.OrderFixtures.order_fixture(branch.id, product: shared)
      end

      conn = init_test_session(conn, %{"staff_id" => staff.id})
      {:ok, view, _} = live(conn, ~p"/staff/dashboard")
      assert has_element?(view, "#dashboard-top-products-plot")
      assert has_element?(view, "#dashboard-product-#{shared.id}")
      assert has_element?(view, "#dashboard-branch-#{first.id}")
      refute has_element?(view, "#dashboard-branch-#{first.id} a[href*='problem=true']")
    end

    test "all-branch today uses each branch's local date", %{conn: conn} do
      east = insert(:branch)
      west = insert(:branch)

      Delivest.Repo.insert!(%Delivest.Identity.Branch.BranchInfo{
        branch_id: east.id,
        timezone: "Pacific/Kiritimati"
      })

      Delivest.Repo.insert!(%Delivest.Identity.Branch.BranchInfo{
        branch_id: west.id,
        timezone: "Pacific/Honolulu"
      })

      staff = insert(:staff, role: insert(:role, permissions: ["statistics.read", "orders.read"]))
      insert(:staff_branch, staff: staff, branch: east)
      insert(:staff_branch, staff: staff, branch: west)

      orders =
        for {branch, zone} <- [{east, "Pacific/Kiritimati"}, {west, "Pacific/Honolulu"}] do
          date = Delivest.LocalTime.today(zone)
          at = DateTime.new!(date, ~T[12:00:00], zone) |> DateTime.shift_zone!("Etc/UTC")
          order = Delivest.OrderFixtures.order_fixture(branch.id, price: 10_000)
          order |> Ecto.Changeset.change(inserted_at: at) |> Delivest.Repo.update!()
        end

      assert Delivest.LocalTime.today("Pacific/Kiritimati") !=
               Delivest.LocalTime.today("Pacific/Honolulu")

      conn = init_test_session(conn, %{"staff_id" => staff.id})
      {:ok, view, html} = live(conn, ~p"/staff/dashboard")
      assert Enum.all?(orders, &has_element?(view, "#dashboard-order-#{&1.id}"))
      assert html =~ "200 ₽"
    end

    test "latest orders takes the newest eight across branches", %{conn: conn} do
      first = insert(:branch)
      second = insert(:branch)
      staff = insert(:staff, role: insert(:role, permissions: ["orders.read"]))
      insert(:staff_branch, staff: staff, branch: first)
      insert(:staff_branch, staff: staff, branch: second)
      zone = Delivest.LocalTime.timezone(first.id)

      start =
        DateTime.new!(Delivest.LocalTime.today(zone), ~T[12:00:00], zone)
        |> DateTime.shift_zone!("Etc/UTC")

      orders =
        for {branch, index} <-
              Enum.with_index(List.duplicate(first, 5) ++ List.duplicate(second, 5)) do
          order = Delivest.OrderFixtures.order_fixture(branch.id)

          order
          |> Ecto.Changeset.change(inserted_at: DateTime.add(start, index * 60))
          |> Delivest.Repo.update!()
        end

      conn = init_test_session(conn, %{"staff_id" => staff.id})
      {:ok, view, _} = live(conn, ~p"/staff/dashboard")
      assert has_element?(view, "#dashboard-branch-#{first.id} a[href*='problem=true']")
      refute has_element?(view, "#dashboard-widget-revenue")
      assert Enum.all?(Enum.take(orders, 2), &(!has_element?(view, "#dashboard-order-#{&1.id}")))
      assert Enum.all?(Enum.drop(orders, 2), &has_element?(view, "#dashboard-order-#{&1.id}"))
    end

    test "redirects unauthenticated staff to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/staff/auth/login"}}} =
               live(conn, ~p"/staff/b/#{insert(:branch)}/dashboard")
    end

    test "renders dashboard for authenticated staff in an active branch", %{conn: conn} do
      branch = insert(:branch, name: "Main Branch")
      staff = insert(:staff)
      insert(:staff_branch, staff: staff, branch: branch)

      conn =
        init_test_session(conn, %{
          "staff_id" => staff.id,
          "active_branch_id" => branch.id
        })

      {:ok, _lv, html} = live(conn, ~p"/staff/b/#{branch}/dashboard")

      assert html =~ "Dashboard"
      assert html =~ "Log out"
    end

    test "shows today's sales and latest orders", %{conn: conn} do
      branch = insert(:branch, name: "Main Branch")
      staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
      insert(:staff_branch, staff: staff, branch: branch)
      order = Delivest.OrderFixtures.order_fixture(branch.id, price: 45_000)

      conn =
        init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

      {:ok, lv, html} = live(conn, ~p"/staff/b/#{branch}/dashboard")

      assert html =~ "450 ₽"
      assert has_element?(lv, "#dashboard-order-#{order.id}")

      assert has_element?(
               lv,
               ~s{#dashboard-order-#{order.id} a[href="/staff/b/#{branch.slug}/orders/#{order.id}"]}
             )

      second = Delivest.OrderFixtures.order_fixture(branch.id, price: 5000)

      send(lv.pid, :reload)
      assert has_element?(lv, "#dashboard-order-#{second.id}")
      assert render(lv) =~ "500 ₽"
    end
  end

  describe "header" do
    setup %{conn: conn} do
      branch = insert(:branch, name: "Main Branch")
      staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
      insert(:staff_branch, staff: staff, branch: branch)

      conn =
        init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

      %{conn: conn, branch: branch}
    end

    test "counts orders awaiting confirmation live", %{conn: conn, branch: branch} do
      Delivest.OrderFixtures.order_fixture(branch.id, price: 10_000)
      {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/dashboard")

      assert has_element?(lv, "#header-new-orders-count", "1")

      Delivest.OrderFixtures.order_fixture(branch.id, price: 10_000)
      assert has_element?(lv, "#header-new-orders-count", "2")
    end

    test "dashboard shows current attention counts and links to the branch's problem orders", %{
      conn: conn,
      branch: branch
    } do
      {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/dashboard")
      assert has_element?(lv, "#dashboard-attention-empty")
      refute has_element?(lv, "#dashboard-alert-problem")

      order = Delivest.OrderFixtures.order_fixture(branch.id, price: 10_000)

      order
      |> Ecto.Changeset.change(
        crm: %Delivest.Oms.Order.CrmSync{provider: "frontpad", status: "failed"}
      )
      |> Delivest.Repo.update!()

      {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/dashboard")
      assert has_element?(lv, "#dashboard-alert-problem", "1")
      assert has_element?(lv, ~s(#dashboard-alert-problem a[href*="problem=true"]))
      assert has_element?(lv, ~s(#dashboard-alert-waiting a[href*="status=created"]))
      assert has_element?(lv, ~s(#dashboard-alert-ready a[href*="status=ready"]))
    end

    test "profile controls stay in the sidebar and scope lives in the header", %{
      conn: conn,
      branch: branch
    } do
      {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/dashboard")

      assert has_element?(lv, "#staff-profile-trigger[aria-expanded='false']")
      assert has_element?(lv, "#staff-profile-menu a[href='/staff/auth/log_out']")
      assert has_element?(lv, "#staff-header #header-branch")
      refute has_element?(lv, "#main-sidebar #header-branch")
      refute has_element?(lv, "#staff-header #sidebar-toggle")
    end

    test "theme switch lives in the user menu and new order is not in the header", %{
      conn: conn,
      branch: branch
    } do
      {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/dashboard")

      assert has_element?(lv, "#staff-profile-menu #header-theme-dark")
      assert has_element?(lv, "#staff-profile-menu #header-theme-light")
      assert has_element?(lv, "main #staff-page-header h1")
      assert render(element(lv, "#staff-page-header")) =~ "Today"
      assert has_element?(lv, "#staff-header #command-palette-trigger")
      refute has_element?(lv, "#main-sidebar #command-palette-trigger")
    end
  end
end
