defmodule DelivestWeb.Staff.MenuLive.PopularTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Popular

  test "static page has the shared product navigation before LiveView connects", %{conn: conn} do
    branch = insert(:branch)
    conn = sign_in(conn, branch, ["products.read", "products.update"])

    document =
      conn
      |> get(~p"/staff/b/#{branch}/menu/popular")
      |> html_response(200)
      |> LazyHTML.from_document()

    assert Enum.count(
             LazyHTML.query(document, "#staff-context-navigation #staff-section-navigation")
           ) == 1

    assert Enum.count(
             LazyHTML.query(
               document,
               "#staff-context-navigation #staff-section-navigation #product-section-tab-collections[aria-current='page']"
             )
           ) == 1

    assert Enum.empty?(LazyHTML.query(document, "#staff-header #staff-section-navigation"))
  end

  test "popular page uses one shared navigation and authorized header Save action", %{conn: conn} do
    branch = insert(:branch)

    {:ok, lv, _} =
      live(
        sign_in(conn, branch, ["products.read", "products.update"]),
        ~p"/staff/b/#{branch}/menu/popular"
      )

    assert has_element?(
             lv,
             "#staff-context-navigation #staff-section-navigation #product-section-tab-collections[aria-current='page']"
           )

    assert has_element?(lv, "main #popular-toolbar h1:not(.sr-only)", "Popular products")

    assert has_element?(
             lv,
             "#popular-toolbar a[href='/staff/b/#{branch.slug}/products/collections'][aria-label='Back']"
           )

    refute has_element?(lv, "#collections-tab-popular")
    refute has_element?(lv, "#collections-tab-suggested")
    refute has_element?(lv, "#staff-header-context")

    assert Enum.count(
             LazyHTML.query(LazyHTML.from_fragment(render(lv)), "#staff-section-navigation")
           ) == 1

    assert has_element?(
             lv,
             "#popular-toolbar .staff-page-toolbar-actions button[form='popular-settings']"
           )

    refute has_element?(lv, "#popular-toolbar #popular-more-actions #popular-add-products")

    refute has_element?(lv, "#popular-toolbar .staff-page-toolbar-actions details > summary")
  end

  defp sign_in(conn, branch, permissions) do
    staff = insert(:staff, role: insert(:role, permissions: permissions))
    insert(:staff_branch, staff: staff, branch: branch)
    init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
  end

  test "manual mode picks and unpicks products", %{conn: conn} do
    branch = insert(:branch)
    product = insert_branch_product(branch.id, name: "Пицца")

    {:ok, lv, _html} =
      live(
        sign_in(conn, branch, ["products.read", "products.update"]),
        ~p"/staff/b/#{branch}/menu/popular"
      )

    lv
    |> form("#popular-settings", popular: %{mode: "manual"})
    |> render_submit()

    lv |> element("#popular-add-products") |> render_click()
    lv |> element("#popular-picker button[phx-click=collapse]") |> render_click()
    lv |> element("#popular-picker-product-#{product.id} input") |> render_click()
    assert Popular.list_products(branch.id) == []
    lv |> element("#popular-picker button[phx-click=save]") |> render_click()
    render(lv)

    assert Enum.map(Popular.list_products(branch.id), & &1.id) == [product.id]

    lv |> element("#popular-picked-#{product.id} button[aria-label=Remove]") |> render_click()

    assert Popular.list_products(branch.id) == []
  end

  test "the page is read-only without products.update", %{conn: conn} do
    branch = insert(:branch)

    {:ok, lv, _html} =
      live(sign_in(conn, branch, ["products.read"]), ~p"/staff/b/#{branch}/menu/popular")

    refute has_element?(lv, "button[form=popular-settings]")

    assert has_element?(
             lv,
             "#staff-context-navigation #staff-section-navigation #product-section-tab-collections[aria-current='page']"
           )

    refute has_element?(lv, "#popular-toolbar .staff-page-toolbar-actions")
    refute has_element?(lv, "#popular-add-products")
    assert has_element?(lv, "#popular_show_in_menu[disabled]")
    assert has_element?(lv, "#popular_show_in_cart[disabled]")
  end

  test "display options save independently", %{conn: conn} do
    branch = insert(:branch)

    {:ok, lv, _} =
      live(
        sign_in(conn, branch, ["products.read", "products.update"]),
        ~p"/staff/b/#{branch}/menu/popular"
      )

    assert has_element?(lv, "#popular_show_in_menu")
    assert has_element?(lv, "#popular_show_in_cart[checked]")

    lv
    |> form("#popular-settings", popular: %{show_in_menu: "true", show_in_cart: "false"})
    |> render_submit()

    assert %{show_in_menu: true, show_in_cart: false} = Popular.get_settings(branch.id)
  end

  test "mode selection is a draft until Save and survives catalog refresh", %{conn: conn} do
    branch = insert(:branch)

    {:ok, lv, _} =
      live(
        sign_in(conn, branch, ["products.read", "products.update"]),
        ~p"/staff/b/#{branch}/menu/popular"
      )

    assert has_element?(lv, "#popular_mode option[value='off'][selected]")
    assert has_element?(lv, "#popular_mode option[value='auto']")
    assert has_element?(lv, "#popular_mode option[value='manual']")
    refute has_element?(lv, "#popular_auto_limit")

    lv |> form("#popular-settings", popular: %{mode: "auto"}) |> render_change()
    assert has_element?(lv, "#popular_auto_limit")
    assert has_element?(lv, "#popular-settings-dirty")
    assert has_element?(lv, "#popular-off-empty")
    assert Popular.get_settings(branch.id).mode == :off

    lv |> form("#popular-settings", popular: %{mode: "off"}) |> render_change()
    refute has_element?(lv, "#popular-settings-dirty")

    lv |> form("#popular-settings", popular: %{mode: "auto"}) |> render_change()

    send(lv.pid, :catalog_changed)
    assert has_element?(lv, "#popular_auto_limit")
    assert has_element?(lv, "#popular-settings-dirty")

    lv |> form("#popular-settings", popular: %{mode: "auto", auto_limit: "0"}) |> render_submit()
    assert has_element?(lv, "#popular_auto_limit")
    assert Popular.get_settings(branch.id).mode == :off

    lv |> form("#popular-settings", popular: %{mode: "auto", auto_limit: "4"}) |> render_submit()
    assert Popular.get_settings(branch.id).mode == :auto
    refute has_element?(lv, "#popular-settings-dirty")
    assert has_element?(lv, "#popular-preview-auto")
  end

  test "auto mode offers an authorized refresh", %{conn: conn} do
    branch = insert(:branch)

    {:ok, editable, _} =
      live(
        sign_in(conn, branch, ["products.read", "products.update"]),
        ~p"/staff/b/#{branch}/menu/popular"
      )

    editable |> form("#popular-settings", popular: %{mode: "auto"}) |> render_submit()
    assert has_element?(editable, "#popular-toolbar #popular-recalculate")

    assert has_element?(
             editable,
             "#popular-toolbar .staff-page-toolbar-actions details > summary",
             "More"
           )

    editable |> element("#popular-recalculate") |> render_click()
    assert Popular.get_settings(branch.id).calculated_at

    {:ok, readonly, _} =
      live(sign_in(build_conn(), branch, ["products.read"]), ~p"/staff/b/#{branch}/menu/popular")

    refute has_element?(readonly, "#popular-recalculate")
  end

  test "picker keeps draft through search and discards it on cancel", %{conn: conn} do
    branch = insert(:branch)
    product = insert_branch_product(branch.id, name: "Борщ")

    {:ok, lv, _} =
      live(
        sign_in(conn, branch, ["products.read", "products.update"]),
        ~p"/staff/b/#{branch}/menu/popular"
      )

    lv |> form("#popular-settings", popular: %{mode: "manual"}) |> render_submit()
    lv |> element("#popular-add-products") |> render_click()
    refute has_element?(lv, "#popular-picker-product-#{product.id}")
    lv |> element("#popular-picker button[phx-click=collapse]") |> render_click()
    lv |> element("#popular-picker-product-#{product.id} input") |> render_click()
    lv |> form("#popular-picker-search", %{search: "нет"}) |> render_change()
    assert has_element?(lv, "#popular-picker-categories", "No products")
    lv |> form("#popular-picker-search", %{search: "Борщ"}) |> render_change()
    assert has_element?(lv, "#popular-picker-product-#{product.id} input[checked]")
    lv |> element("#popular-picker button.btn-outline[phx-click=cancel]") |> render_click()
    render(lv)
    assert Popular.list_products(branch.id) == []
  end
end
