defmodule DelivestWeb.Staff.MenuLive.PopularTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Popular

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

    lv |> element("#popular-catalog-#{product.id} input[type=checkbox]") |> render_click()

    assert Enum.map(Popular.list_products(branch.id), & &1.id) == [product.id]

    lv |> element("#popular-picked-#{product.id} button[aria-label=Remove]") |> render_click()

    assert Popular.list_products(branch.id) == []
  end

  test "the page is read-only without products.update", %{conn: conn} do
    branch = insert(:branch)

    {:ok, lv, _html} =
      live(sign_in(conn, branch, ["products.read"]), ~p"/staff/b/#{branch}/menu/popular")

    refute has_element?(lv, "button[form=popular-settings]")
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
end
