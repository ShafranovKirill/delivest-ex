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
        ~p"/staff/b/#{ctx.branch}/products/stops"
      )

    refute html =~ "Пельмени"
    lv |> element("#stop-add-products") |> render_click()
    lv |> element("#stop-picker button[phx-click=collapse]") |> render_click()
    lv |> element("#stop-picker-product-#{ctx.soup.id} input") |> render_click()
    refute Stops.stopped?(ctx.branch.id, ctx.soup.id)
    lv |> element("#stop-picker button[phx-click=save]") |> render_click()
    render(lv)

    assert Stops.stopped?(ctx.branch.id, ctx.soup.id)

    lv |> element("#stop-add-products") |> render_click()
    lv |> element("#stop-picker button[phx-click=collapse]") |> render_click()
    lv |> element("#stop-picker-product-#{ctx.soup.id} input") |> render_click()
    lv |> element("#stop-picker button.btn-outline[phx-click=cancel]") |> render_click()
    render(lv)
    assert Stops.stopped?(ctx.branch.id, ctx.soup.id)

    lv |> element("#stop-add-products") |> render_click()
    lv |> element("#stop-picker button[phx-click=collapse]") |> render_click()
    lv |> element("#stop-picker-product-#{ctx.soup.id} input") |> render_click()
    lv |> element("#stop-picker button[phx-click=save]") |> render_click()
    render(lv)
    refute Stops.stopped?(ctx.branch.id, ctx.soup.id)

    lv |> element("#stop-add-products") |> render_click()
    lv |> element("#stop-picker button[phx-click=collapse]") |> render_click()
    lv |> element("#stop-picker-product-#{ctx.soup.id} input") |> render_click()
    lv |> element("#stop-picker button[phx-click=save]") |> render_click()
    render(lv)
    assert Stops.stopped?(ctx.branch.id, ctx.soup.id)

    html = render(lv)
    assert html =~ "Борщ"
    refute html =~ "Пельмени"

    lv |> element("#product-stop-#{ctx.soup.id} button[phx-click=resume]") |> render_click()
    refute Stops.stopped?(ctx.branch.id, ctx.soup.id)
  end

  test "without stops.update the list is read only", ctx do
    {:ok, lv, _html} =
      live(
        sign_in(ctx.conn, ctx.branch, ["products.read"]),
        ~p"/staff/b/#{ctx.branch}/products/stops"
      )

    refute has_element?(lv, "#product-stop-#{ctx.soup.id} button")
    refute has_element?(lv, "#stop-add-products")
  end

  test "products are recommended and searched", ctx do
    insert_branch_product(ctx.branch.id, name: "Пельмени")

    {:ok, lv, _html} =
      live(
        sign_in(ctx.conn, ctx.branch, ["products.read", "products.update"]),
        ~p"/staff/b/#{ctx.branch}/products/suggested"
      )

    lv |> element("#suggested-add-products") |> render_click()
    lv |> element("#suggested-picker button[phx-click=collapse]") |> render_click()
    lv |> element("#suggested-picker-product-#{ctx.soup.id} input") |> render_click()
    assert {:ok, %{suggested: false}} = Net.get_branch_product(ctx.branch.id, ctx.soup.id)
    lv |> element("#suggested-picker button[phx-click=save]") |> render_click()
    render(lv)
    assert {:ok, %{suggested: true}} = Net.get_branch_product(ctx.branch.id, ctx.soup.id)
    assert has_element?(lv, "#suggested-list-#{ctx.soup.id}")
    refute has_element?(lv, "#suggested-list-#{ctx.soup.id} input")
  end

  test "the sidebar groups the menu pages", ctx do
    {:ok, _lv, html} =
      live(
        sign_in(ctx.conn, ctx.branch, ["categories.read", "products.read", "orders.read"]),
        ~p"/staff/b/#{ctx.branch}/products/stops"
      )

    assert html =~ ~s(id="nav-group-menu")
    assert html =~ ~s(href="/staff/b/#{ctx.branch.slug}/products/suggested")
    refute html =~ ~s(id="nav-group-orders")
    assert html =~ ~s(href="/staff/b/#{ctx.branch.slug}/orders")
  end

  test "the sidebar splits branch pages from network pages", ctx do
    {:ok, lv, _html} =
      live(
        sign_in(ctx.conn, ctx.branch, ["products.read", "clients.read"]),
        ~p"/staff/b/#{ctx.branch}/products/tags"
      )

    assert has_element?(lv, "#header-branch", ctx.branch.name)

    refute has_element?(
             lv,
             ~s(#nav-section-branch a[href="/staff/b/#{ctx.branch.slug}/products/stops"])
           )

    assert has_element?(lv, ~s(#nav-section-network a[href="/staff/clients"]))
    refute has_element?(lv, ~s(#main-sidebar a[href="/staff/b/#{ctx.branch.slug}/products/tags"]))

    assert has_element?(
             lv,
             ~s(#main-sidebar a.menu-active[href="/staff/b/#{ctx.branch.slug}/products"])
           )
  end
end
