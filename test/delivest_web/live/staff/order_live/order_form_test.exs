defmodule DelivestWeb.Staff.OrderLive.OrderFormTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Oms.{Carts, Order}
  alias Delivest.Repo

  setup %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    insert(:staff_branch, staff: staff, branch: branch)

    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    %{conn: conn, branch: branch, staff: staff, product: insert_branch_product(branch.id)}
  end

  test "cart survives a remount", %{conn: conn, product: product} do
    {:ok, lv, _html} = live(conn, ~p"/staff/orders/new")
    render_click(lv, "add_item", %{"product-id" => product.id})

    {:ok, _lv, html} = live(conn, ~p"/staff/orders/new")

    assert html =~ product.name
  end

  test "order without phone is created", %{conn: conn, branch: branch, product: product} do
    {:ok, lv, _html} = live(conn, ~p"/staff/orders/new")
    render_click(lv, "add_item", %{"product-id" => product.id})

    lv
    |> form("#order-details-form", order: %{customer_phone: "+7"})
    |> render_submit()

    assert_redirect(lv, ~p"/staff/orders")
    assert [%Order{client_id: nil}] = Repo.all(Order) |> Enum.filter(&(&1.branch_id == branch.id))
  end

  test "unsaved edits do not touch the order", %{conn: conn, branch: branch, product: product} do
    order = order_fixture(branch.id, product: product)

    {:ok, lv, _html} = live(conn, ~p"/staff/orders/#{order.id}/edit")
    render_click(lv, "add_item", %{"product-id" => product.id})

    assert Carts.get_cart_by_id(order.cart_id).total_quantity == 1
    assert [%{quantity: 1}] = Repo.preload(Repo.reload!(order), :items).items
  end

  test "edit saves the cart into the order", %{conn: conn, branch: branch, product: product} do
    order = order_fixture(branch.id, product: product)

    {:ok, lv, _html} = live(conn, ~p"/staff/orders/#{order.id}/edit")
    render_click(lv, "add_item", %{"product-id" => product.id})

    lv
    |> form("#order-details-form")
    |> render_submit()

    assert_redirect(lv, ~p"/staff/orders")
    assert [%{quantity: 2}] = Repo.preload(Repo.reload!(order), :items, force: true).items
  end

  test "crm orders cannot be opened for edit", %{conn: conn, branch: branch} do
    order = order_fixture(branch.id, attrs: %{"status" => "crm"})

    assert {:error, {:redirect, %{to: "/staff/orders"}}} =
             live(conn, ~p"/staff/orders/#{order.id}/edit")
  end
end
