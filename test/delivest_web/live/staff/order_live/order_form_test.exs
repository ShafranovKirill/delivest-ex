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

  test "a known client is recognised and their address is one click away", %{
    conn: conn,
    branch: branch,
    product: product
  } do
    client = insert(:client, phone: "+79995551122", name: "Анна")

    {:ok, address} =
      Delivest.Identity.create_client_address(client.id, %{
        "city" => "Москва",
        "street" => "Ленина",
        "house" => "5"
      })

    {:ok, lv, _html} = live(conn, ~p"/staff/orders/new")
    render_click(lv, "add_item", %{"product-id" => product.id})

    lv
    |> form("#order-details-form",
      order: %{customer_phone: "+79995551122", fulfillment_type: "delivery"}
    )
    |> render_change()

    assert has_element?(lv, "#known-client", "Анна")
    assert has_element?(lv, ~s{input[name="order[customer_name]"][value="Анна"]})

    lv |> element("#use-address-#{address.id}") |> render_click()
    assert has_element?(lv, ~s{input[name="order[address][street]"][value="Ленина"]})

    lv |> form("#order-details-form") |> render_submit()

    assert [%Order{client_id: client_id, address: %{street: "Ленина", house: "5"}}] =
             Repo.all(Order) |> Enum.filter(&(&1.branch_id == branch.id))

    assert client_id == client.id
  end

  test "as soon as possible drops the requested time", %{
    conn: conn,
    branch: branch,
    product: product
  } do
    tomorrow =
      NaiveDateTime.utc_now() |> NaiveDateTime.add(1, :day) |> NaiveDateTime.truncate(:second)

    order = order_fixture(branch.id, product: product, attrs: %{"cook_by" => tomorrow})
    assert Repo.reload!(order).cook_by

    {:ok, lv, _html} = live(conn, ~p"/staff/orders/#{order.id}/edit")
    lv |> form("#order-details-form", order: %{timing: "asap"}) |> render_submit()

    assert Repo.reload!(order).cook_by == nil
  end
end
