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

    assert Enum.count(LazyHTML.query(document, "main #staff-section-navigation")) == 1

    assert Enum.count(
             LazyHTML.query(
               document,
               "main #staff-section-navigation #product-section-tab-popular[aria-current='page']"
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
             "main #staff-section-navigation #product-section-tab-popular[aria-current='page']"
           )

    assert has_element?(lv, "main #staff-page-header h1", "Popular products")
    refute has_element?(lv, "#staff-header-context")

    assert Enum.count(
             LazyHTML.query(LazyHTML.from_fragment(render(lv)), "#staff-section-navigation")
           ) == 1

    assert render(element(lv, "#staff-page-header-actions")) =~ ~s(form="popular-settings")
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
             "main #staff-section-navigation #product-section-tab-popular[aria-current='page']"
           )

    refute has_element?(lv, "#staff-page-header-actions")
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

  test "auto mode offers an authorized refresh", %{conn: conn} do
    branch = insert(:branch)

    {:ok, editable, _} =
      live(
        sign_in(conn, branch, ["products.read", "products.update"]),
        ~p"/staff/b/#{branch}/menu/popular"
      )

    editable |> form("#popular-settings", popular: %{mode: "auto"}) |> render_submit()
    assert has_element?(editable, "#popular-recalculate")
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
