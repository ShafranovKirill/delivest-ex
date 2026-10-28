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

  test "the header switches between accessible branches in place", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/staff/b/#{ctx.own}/products")

    assert has_element?(lv, "#header-branch-#{ctx.own.id}.menu-active")

    assert has_element?(
             lv,
             ~s(#header-branch-#{ctx.second.id}[href="/staff/branches/select/#{ctx.second.id}?to=%2Fproducts"])
           )

    refute has_element?(lv, "#header-branch-#{ctx.foreign.id}")
  end

  test "two tabs with different branches do not affect each other", ctx do
    {:ok, own_tab, _html} = live(ctx.conn, ~p"/staff/b/#{ctx.own}/orders")
    {:ok, second_tab, _html} = live(ctx.conn, ~p"/staff/b/#{ctx.second}/orders")

    conn = get(ctx.conn, ~p"/staff/branches/select/#{ctx.second.id}")
    assert redirected_to(conn) == ~p"/staff/b/#{ctx.second}/dashboard"

    assert render(own_tab) =~ "Own"
    assert render(second_tab) =~ "Second"
    assert has_element?(own_tab, ~s(#main-sidebar a[href="/staff/b/#{ctx.own.slug}/products"]))
  end

  test "the switcher keeps the section and remembers the branch", ctx do
    conn = get(ctx.conn, ~p"/staff/branches/select/#{ctx.second.id}?to=/products/stops")
    assert redirected_to(conn) == ~p"/staff/b/#{ctx.second}/products/stops"
    assert get_session(conn, :active_branch_id) == ctx.second.id

    conn = conn |> recycle() |> get(~p"/staff")
    assert redirected_to(conn) == ~p"/staff/b/#{ctx.second}/dashboard"

    conn = get(ctx.conn, ~p"/staff/branches/select/#{ctx.own.id}?to=//evil.example")
    assert redirected_to(conn) == ~p"/staff/b/#{ctx.own}/dashboard"

    conn = get(ctx.conn, ~p"/staff/branches/select/#{ctx.foreign.id}")
    assert redirected_to(conn) == ~p"/staff/branches/select"
  end

  test "the home page goes to the branch choice when access is gone", ctx do
    conn =
      ctx.conn
      |> init_test_session(%{"staff_id" => ctx.staff.id, "active_branch_id" => ctx.foreign.id})
      |> get(~p"/staff")

    assert redirected_to(conn) == ~p"/staff/branches/select"
  end

  test "an open card leads to the list of the section in another branch" do
    id = Ecto.UUID.generate()

    assert StaffBranchPath.section("/staff/b/own/orders/#{id}/edit") == "/orders"
    assert StaffBranchPath.section("/staff/b/own/products/stops") == "/products/stops"
    assert StaffBranchPath.section("/staff/clients") == nil
    refute StaffBranchPath.valid_section?("//evil.example")
  end
end
