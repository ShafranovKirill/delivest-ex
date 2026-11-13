defmodule DelivestWeb.Staff.BranchInUrlTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias DelivestWeb.StaffBranchPath

  setup %{conn: conn} do
    own = insert(:branch, name: "Own")
    second = insert(:branch, name: "Second")
    foreign = insert(:branch, name: "Foreign")
    staff = insert(:staff, role: insert(:role, permissions: ["orders.read", "products.read"]))
    insert(:staff_branch, staff: staff, branch: own)
    insert(:staff_branch, staff: staff, branch: second)

    %{
      conn: init_test_session(conn, %{"staff_id" => staff.id}),
      staff: staff,
      own: own,
      second: second,
      foreign: foreign
    }
  end

  test "a foreign or unknown branch in the address is not opened", ctx do
    assert {:error, {:redirect, %{to: "/staff/branches/select", flash: %{"error" => _}}}} =
             live(ctx.conn, ~p"/staff/b/#{ctx.foreign}/orders")

    assert {:error, {:redirect, %{to: "/staff/branches/select"}}} =
             live(ctx.conn, "/staff/b/no-such-branch/orders")
  end

  test "the sidebar switches between accessible branches in place", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/staff/b/#{ctx.own}/products")

    assert has_element?(lv, "#staff-header #header-branch-#{ctx.own.id}.menu-active")

    assert has_element?(
             lv,
             ~s(#header-branch-#{ctx.second.id}[href^="/staff/branches/select/#{ctx.second.id}?"][href*="from="])
           )

    refute has_element?(lv, "#header-branch-#{ctx.foreign.id}")
  end

  test "two tabs with different branches do not affect each other", ctx do
    {:ok, own_tab, _html} = live(ctx.conn, ~p"/staff/b/#{ctx.own}/orders")
    {:ok, second_tab, _html} = live(ctx.conn, ~p"/staff/b/#{ctx.second}/orders")

    conn = get(ctx.conn, ~p"/staff/branches/select/#{ctx.second.id}")
    assert redirected_to(conn) == ~p"/staff/b/#{ctx.second}/orders"

    assert render(own_tab) =~ "Own"
    assert render(second_tab) =~ "Second"
    assert has_element?(own_tab, ~s(#main-sidebar a[href="/staff/b/#{ctx.own.slug}/products"]))
  end

  test "the switcher keeps the section and remembers the branch", ctx do
    conn = get(ctx.conn, ~p"/staff/branches/select/#{ctx.second.id}?to=/products/stops")
    assert redirected_to(conn) == ~p"/staff/b/#{ctx.second}/products/stops"
    assert get_session(conn, :active_branch_id) == ctx.second.id

    conn = conn |> recycle() |> get(~p"/staff")
    assert redirected_to(conn) == ~p"/staff/b/#{ctx.second}/orders"

    conn = get(ctx.conn, ~p"/staff/branches/select/#{ctx.own.id}?to=//evil.example")
    assert redirected_to(conn) == ~p"/staff/branches/select"

    conn = get(ctx.conn, ~p"/staff/branches/select/#{ctx.foreign.id}")
    assert redirected_to(conn) == ~p"/staff/branches/select"
  end

  test "the home page goes to the all-branch dashboard when access is gone", ctx do
    conn =
      ctx.conn
      |> init_test_session(%{"staff_id" => ctx.staff.id, "active_branch_id" => ctx.foreign.id})
      |> get(~p"/staff")

    assert redirected_to(conn) == ~p"/staff/dashboard"
  end

  test "all branches clears the active branch and ignores a stale session", ctx do
    conn =
      init_test_session(ctx.conn, %{"staff_id" => ctx.staff.id, "active_branch_id" => ctx.own.id})

    {:ok, all, _} = live(conn, ~p"/staff/dashboard")
    assert has_element?(all, "#header-branch-all.menu-active")
    assert has_element?(all, ~s(#main-sidebar a[href="/staff/dashboard"]))
    refute has_element?(all, ~s(#main-sidebar a[href="/staff/b/#{ctx.own.slug}/dashboard"]))

    conn = get(conn, ~p"/staff/branches/all")
    assert redirected_to(conn) == ~p"/staff/dashboard"
    assert get_session(conn, :active_branch_id) == nil
    assert redirected_to(conn |> recycle() |> get(~p"/staff")) == ~p"/staff/dashboard"
  end

  test "an open card leads to the list of the section in another branch" do
    id = Ecto.UUID.generate()

    assert StaffBranchPath.section("/staff/b/own/orders/#{id}/edit") == "/orders"
    assert StaffBranchPath.section("/staff/b/own/products/stops") == "/products/stops"
    assert StaffBranchPath.section("/staff/b/own/products/tags/#{id}/edit") == "/products/tags"
    assert StaffBranchPath.section("/staff/clients") == nil
    refute StaffBranchPath.valid_section?("//evil.example")
  end

  test "scope policy keeps only compatible list filters and drops object identity", ctx do
    {:ok, %{path: path}} =
      StaffBranchPath.transition(
        "/staff/b/#{ctx.own.slug}/products?search=pizza&page=3&category_id=old&is_active=true",
        {:branch, ctx.second.slug}
      )

    assert path == "/staff/b/#{ctx.second.slug}/products?is_active=true&search=pizza" or
             path == "/staff/b/#{ctx.second.slug}/products?search=pizza&is_active=true"

    order_id = Ecto.UUID.generate()

    assert {:ok, %{path: orders_path}} =
             StaffBranchPath.transition(
               "/staff/b/#{ctx.own.slug}/orders/#{order_id}",
               {:branch, ctx.second.slug}
             )

    assert orders_path == "/staff/b/#{ctx.second.slug}/orders"

    assert {:ok, %{path: hours_path}} =
             StaffBranchPath.transition(
               "/staff/branches/#{ctx.own.slug}/edit/hours",
               {:branch, ctx.second.slug}
             )

    assert hours_path == "/staff/branches/#{ctx.second.slug}/edit/hours"
  end

  test "network counterparts and explicit fallback do not silently change sections", ctx do
    assert {:ok, %{path: "/staff/statistics?period=today"}} =
             StaffBranchPath.transition(
               "/staff/b/#{ctx.own.slug}/statistics?period=today&link_id=old",
               :network
             )

    assert {:ok, %{path: integrations_path}} =
             StaffBranchPath.transition("/staff/integrations", {:branch, ctx.second.slug})

    assert integrations_path == "/staff/b/#{ctx.second.slug}/integrations"

    assert {:fallback, %{path: overview_path}} =
             StaffBranchPath.transition("/staff/franchise/brand", {:branch, ctx.second.slug})

    assert overview_path == "/staff/b/#{ctx.second.slug}/dashboard"

    assert {:choice, %{stay: stay_path, overview: "/staff/dashboard"}} =
             StaffBranchPath.transition("/staff/b/#{ctx.own.slug}/products", :network)

    assert stay_path == "/staff/b/#{ctx.own.slug}/products"

    assert :error == StaffBranchPath.transition("https://evil.example/staff/dashboard", :network)
    assert :error == StaffBranchPath.transition("/staff/b/#{ctx.own.slug}/invented", :network)
    refute StaffBranchPath.valid_section?("/invented")
  end

  test "settings summary changes only URL scope and keeps a safe status filter", ctx do
    source = "/staff/settings?branch=#{ctx.own.slug}&filter=attention&page=3&selected=old"

    assert {:ok, %{path: branch_path}} =
             StaffBranchPath.transition(source, {:branch, ctx.second.slug})

    assert branch_path == "/staff/settings?branch=#{ctx.second.slug}&filter=attention"

    assert {:ok, %{path: network_path}} = StaffBranchPath.transition(source, :network)
    assert network_path == "/staff/settings?filter=attention"

    assert {:ok, %{path: "/staff/settings"}} =
             StaffBranchPath.transition(
               "/staff/settings?filter=unknown&branch=#{ctx.own.slug}",
               :network
             )

    conn =
      get(
        ctx.conn,
        "/staff/branches/select/#{ctx.second.id}?" <> URI.encode_query(%{"from" => source})
      )

    assert redirected_to(conn) == branch_path

    conn = get(ctx.conn, "/staff/branches/all?" <> URI.encode_query(%{"from" => source}))
    assert redirected_to(conn) == network_path
  end

  test "shared integration routes keep network scope when selecting a point", ctx do
    for provider <- ~w(dadata zvonok yookassa yandex-eda) do
      network_path = "/staff/integrations/#{provider}"

      assert {:ok, %{path: ^network_path}} =
               StaffBranchPath.transition(
                 "/staff/b/#{ctx.own.slug}/integrations/#{provider}",
                 {:branch, ctx.second.slug}
               )

      assert {:ok, %{path: ^network_path}} =
               StaffBranchPath.transition(network_path, {:branch, ctx.second.slug})
    end
  end

  test "controller requires an explicit overview choice and rejects arbitrary destinations",
       ctx do
    source = "/staff/branches/#{ctx.own.slug}/edit/hours"

    conn =
      get(
        ctx.conn,
        "/staff/branches/select/#{ctx.second.id}?" <> URI.encode_query(%{"from" => source})
      )

    assert redirected_to(conn) == "/staff/branches/#{ctx.second.slug}/edit/hours"

    from = "/staff/b/#{ctx.own.slug}/products"
    conn = get(ctx.conn, "/staff/branches/all?" <> URI.encode_query(%{"from" => from}))
    assert redirected_to(conn) == from

    conn =
      get(
        ctx.conn,
        "/staff/branches/all?" <> URI.encode_query(%{"from" => from, "fallback" => "overview"})
      )

    assert redirected_to(conn) == "/staff/dashboard"

    network_from = "/staff/franchise/brand"

    conn =
      get(
        ctx.conn,
        "/staff/branches/select/#{ctx.second.id}?" <> URI.encode_query(%{"from" => network_from})
      )

    assert redirected_to(conn) == network_from

    conn =
      get(
        ctx.conn,
        "/staff/branches/select/#{ctx.second.id}?" <>
          URI.encode_query(%{"from" => network_from, "fallback" => "overview"})
      )

    assert redirected_to(conn) == "/staff/b/#{ctx.second.slug}/dashboard"

    conn = get(ctx.conn, "/staff/branches/select/#{ctx.second.id}?to=%2Ftotally-fake")
    assert redirected_to(conn) == "/staff/branches/select"

    conn =
      get(
        ctx.conn,
        "/staff/branches/select/#{ctx.second.id}?" <>
          URI.encode_query(%{"from" => "/staff/b/#{ctx.own.slug}/products?search=%"})
      )

    assert redirected_to(conn) == "/staff/branches/select"
  end
end
