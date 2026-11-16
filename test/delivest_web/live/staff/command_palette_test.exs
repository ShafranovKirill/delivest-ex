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

    assert has_element?(lv, "#staff-header #command-palette-trigger[aria-label]")
    refute has_element?(lv, "#main-sidebar #command-palette-trigger")
    assert has_element?(lv, "#command-item-page-orders")
    assert has_element?(lv, "#command-item-page-clients")
  end

  test "aliases open the canonical settings forms", %{conn: conn, branch: branch} do
    {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/dashboard")

    lv |> form("#command-palette-form", %{query: "фронтпад"}) |> render_change()

    assert has_element?(
             lv,
             "#command-item-page-frontpad[href='/staff/b/#{branch.slug}/integrations/frontpad']"
           )

    refute has_element?(lv, "#settings-navigation #settings-nav-frontpad")
    refute has_element?(lv, "#sidebar-settings-navigation #sidebar-settings-nav-frontpad")

    lv |> form("#command-palette-form", %{query: "зоны"}) |> render_change()

    assert has_element?(
             lv,
             "#command-item-page-delivery_settings[href='/staff/b/#{branch.slug}/delivery']"
           )

    lv |> form("#command-palette-form", %{query: "график"}) |> render_change()

    assert has_element?(
             lv,
             "#command-item-page-branch_settings[href='/staff/branches/#{branch.slug}/edit']"
           )

    lv |> form("#command-palette-form", %{query: "бренд"}) |> render_change()
    assert has_element?(lv, "#command-item-page-franchise[href='/staff/franchise']")

    lv |> form("#command-palette-form", %{query: "права"}) |> render_change()
    assert has_element?(lv, "#command-item-page-roles[href='/staff/roles']")

    lv |> form("#command-palette-form", %{query: "бонусы"}) |> render_change()

    assert has_element?(
             lv,
             "#command-item-page-loyalty[href='/staff/marketing/bonuses?branch=#{branch.slug}']"
           )
  end

  test "data transfer search follows actual scope instead of the preferred branch", %{
    conn: conn,
    branch: branch
  } do
    {:ok, network, _} = live(conn, "/staff/franchise")
    network |> form("#command-palette-form", %{query: "Data transfer"}) |> render_change()

    assert has_element?(
             network,
             "#command-item-page-data_transfer[href='/staff/settings/data-transfer']"
           )

    {:ok, scoped, _} = live(conn, "/staff/settings?branch=#{branch.slug}")
    scoped |> form("#command-palette-form", %{query: "Data transfer"}) |> render_change()

    assert has_element?(
             scoped,
             "#command-item-page-data_transfer[href='/staff/settings/data-transfer?branch=#{branch.slug}']"
           )
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
    conn = put_session(conn, "locale", "en")
    {:ok, lv, _html} = live(conn, ~p"/staff/clients")

    lv |> form("#command-palette-form", %{query: "cli"}) |> render_change()

    assert has_element?(lv, "#command-item-page-clients")
  end

  test "finds the clients page in Russian", %{conn: conn} do
    conn = put_session(conn, "locale", "ru")
    {:ok, lv, _html} = live(conn, ~p"/staff/clients")

    lv |> form("#command-palette-form", %{query: "кли"}) |> render_change()

    assert has_element?(lv, "#command-item-page-clients")
  end

  test "network palette asks for a branch and does not search entities in a saved branch", %{
    conn: conn,
    branch: branch
  } do
    product = insert_branch_product(branch.id, name: "Margherita")
    {:ok, network, _} = live(conn, ~p"/staff/clients")

    chooser =
      DelivestWeb.StaffBranchPath.selection_path(
        "/staff/b/#{branch.slug}/products",
        "/staff/clients"
      )

    assert has_element?(network, "#command-item-page-products[href='#{chooser}']")

    assert has_element?(network, "#command-item-page-orders_new[href^='/staff/branches/select?']")
    assert has_element?(network, "#command-item-page-orders_new[href*='orders%2Fnew']")

    network |> form("#command-palette-form", %{query: "Margherita"}) |> render_change()
    refute has_element?(network, "#command-item-product-#{product.id}")

    {:ok, scoped, _} = live(conn, ~p"/staff/b/#{branch}/dashboard")
    scoped |> form("#command-palette-form", %{query: "Margherita"}) |> render_change()
    assert has_element?(scoped, "#command-item-product-#{product.id}")
  end
end
