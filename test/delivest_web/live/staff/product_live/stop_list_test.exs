defmodule DelivestWeb.Staff.ProductLive.StopListTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Net
  alias Delivest.Net.Stops

  defp sign_in(conn, branch, permissions) do
    staff = insert(:staff, role: insert(:role, permissions: permissions))
    insert(:staff_branch, staff: staff, branch: branch)
    init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
  end

  setup do
    branch = insert(:branch, is_active: true)
    %{branch: branch, soup: insert_branch_product(branch.id, name: "Борщ")}
  end

  test "an operator stops a product, filters the stopped ones and lifts it", ctx do
    insert_branch_product(ctx.branch.id, name: "Пельмени")

    {:ok, lv, html} =
      live(
        sign_in(ctx.conn, ctx.branch, ["products.read", "stops.update"]),
        ~p"/staff/products/stops"
      )

    assert html =~ "Борщ"
    assert html =~ "Пельмени"

    lv
    |> element("#product-stop-#{ctx.soup.id} button[phx-value-period=until_resumed]")
    |> render_click()

    assert Stops.stopped?(ctx.branch.id, ctx.soup.id)

    html = lv |> form("#stop-list-filter", %{"only" => "true"}) |> render_change()
    assert html =~ "Борщ"
    refute html =~ "Пельмени"

    lv |> element("#product-stop-#{ctx.soup.id} button[phx-click=resume]") |> render_click()
    refute Stops.stopped?(ctx.branch.id, ctx.soup.id)
  end

  test "without stops.update the list is read only", ctx do
    {:ok, lv, _html} =
      live(sign_in(ctx.conn, ctx.branch, ["products.read"]), ~p"/staff/products/stops")

    refute has_element?(lv, "#product-stop-#{ctx.soup.id} button")
  end

  test "products are recommended and searched", ctx do
    insert_branch_product(ctx.branch.id, name: "Пельмени")

    {:ok, lv, _html} =
      live(
        sign_in(ctx.conn, ctx.branch, ["products.read", "products.update"]),
        ~p"/staff/products/suggested"
      )

    lv |> element("#suggested-list-#{ctx.soup.id} input") |> render_click()
    assert {:ok, %{suggested: true}} = Net.get_branch_product(ctx.branch.id, ctx.soup.id)

    html = lv |> form("#suggested-filter", %{"search" => "пельм"}) |> render_change()
    refute html =~ "Борщ"
    assert html =~ "Пельмени"
  end

  test "the sidebar groups the menu pages", ctx do
    {:ok, _lv, html} =
      live(
        sign_in(ctx.conn, ctx.branch, ["products.read", "orders.read"]),
        ~p"/staff/products/stops"
      )

    assert html =~ ~s(id="nav-group-menu")
    assert html =~ ~s(href="/staff/products/suggested")
    refute html =~ ~s(id="nav-group-orders")
    assert html =~ ~s(href="/staff/orders")
  end
end
