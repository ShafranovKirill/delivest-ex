defmodule DelivestWeb.Staff.CommandPaletteTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  setup %{conn: conn} do
    branch = insert(:branch, name: "Main")
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))

    conn =
      init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    %{conn: conn, branch: branch}
  end

  test "lists pages before anything is typed", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/dashboard")

    assert has_element?(lv, "#command-palette-trigger")
    assert has_element?(lv, "#command-item-page-orders")
    assert has_element?(lv, "#command-item-page-clients")
  end

  test "finds pages, clients and products by the typed text", %{conn: conn, branch: branch} do
    client = insert(:client, name: "Margarita Ivanova")
    product = insert_branch_product(branch.id, name: "Margherita")
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/dashboard")

    lv |> form("#command-palette-form", %{query: "marg"}) |> render_change()

    assert has_element?(lv, "#command-item-client-#{client.id}")
    assert has_element?(lv, "#command-item-product-#{product.id}")
    refute has_element?(lv, "#command-item-page-orders")
  end

  test "shows an empty state when nothing matches", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/dashboard")

    lv |> form("#command-palette-form", %{query: "zzzz"}) |> render_change()

    refute has_element?(lv, "[data-command-item]")
  end

  test "works on network pages without a branch in the address", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/staff/clients")

    lv |> form("#command-palette-form", %{query: "cli"}) |> render_change()

    assert has_element?(lv, "#command-item-page-clients")
  end
end
