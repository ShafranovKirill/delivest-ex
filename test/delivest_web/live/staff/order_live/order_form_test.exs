defmodule DelivestWeb.Staff.OrderLive.OrderFormTest do
  use DelivestWeb.ConnCase, async: true
  use Oban.Testing, repo: Delivest.Repo

  import Phoenix.LiveViewTest
  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Events.Event
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Crm.{BranchSettings, OrderSubscriber, SyncWorker}
  alias Delivest.Integrations.TestCrm
  alias Delivest.Oms.{Carts, Order, OrderTransition}
  alias Delivest.Push.NoteWorker
  alias Delivest.Repo

  setup %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    insert(:staff_branch, staff: staff, branch: branch)

    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    %{conn: conn, branch: branch, staff: staff, product: insert_branch_product(branch.id)}
  end

  test "new order shows only user field errors during validation", %{conn: conn, branch: branch} do
    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/orders/new")
    refute has_element?(view, "#order-details-errors")

    render_change(view, "validate_order", %{
      "order" => %{"branch_id" => "invalid", "cart_id" => "invalid"}
    })

    refute has_element?(view, "#order-details-errors")

    render_change(view, "validate_order", %{"order" => %{"persons" => "-1"}})
    assert has_element?(view, "#order-details-errors a[href='#order_persons']")
    refute has_element?(view, "#order-details-errors a[href='#order_branch_id']")
    refute has_element?(view, "#order-details-errors a[href='#order_cart_id']")
  end

  test "cart survives a remount", %{conn: conn, branch: branch, product: product} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/orders/new")
    render_click(lv, "add_item", %{"product-id" => product.id})

    {:ok, _lv, html} = live(conn, ~p"/staff/b/#{branch}/orders/new")

    assert html =~ product.name
  end

  test "a product with modifiers asks for the choice", %{
    conn: conn,
    branch: branch,
    product: product
  } do
    group = Repo.insert!(%Delivest.Net.ModifierGroup{name: "Добавки", min: 0, max: 2})
    cheese = Repo.insert!(%Delivest.Net.Modifier{group_id: group.id, name: "Сыр", price: 5_000})
    Repo.insert!(%Delivest.Net.ProductModifierGroup{product_id: product.id, group_id: group.id})

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/orders/new")
    assert render_click(lv, "add_item", %{"product-id" => product.id}) =~ "modifier-picker"

    html =
      lv
      |> form("#modifier-picker form", %{"modifiers" => %{group.id => [cheese.id]}})
      |> render_submit()

    refute html =~ "modifier-picker"
    assert html =~ "Сыр"

    [item] = Repo.all(Delivest.Oms.CartItem) |> Enum.filter(&(&1.product_id == product.id))
    assert item.modifiers == [%{"id" => cheese.id, "quantity" => 1}]

    render_click(lv, "add_item", %{"product-id" => product.id <> "~" <> item.modifier_key})
    assert Repo.reload!(item).quantity == 2
  end

  test "order without phone is accepted on creation", %{
    conn: conn,
    branch: branch,
    product: product,
    staff: staff
  } do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/orders/new")
    render_click(lv, "add_item", %{"product-id" => product.id})

    lv
    |> form("#order-details-form", order: %{customer_phone: "+7"})
    |> render_submit()

    assert_redirect(lv, ~p"/staff/b/#{branch}/orders")

    assert [%Order{client_id: nil, status: :accepted} = order] =
             Repo.all(Order) |> Enum.filter(&(&1.branch_id == branch.id))

    assert %OrderTransition{from: :created, to: :accepted, source: :system, staff_id: nil} =
             Repo.get_by!(OrderTransition, order_id: order.id)

    assert %Event{actor: %{"kind" => "staff", "id" => staff_id}} =
             Repo.get_by!(Event, aggregate_id: order.id, type: "order.created")

    assert staff_id == staff.id

    assert %Event{actor: %{"kind" => "system"}} =
             Repo.get_by!(Event, aggregate_id: order.id, type: "order.status_changed")
  end

  test "create-only staff can create an accepted order", %{
    conn: conn,
    branch: branch,
    product: product,
    staff: staff
  } do
    staff.role_id
    |> then(&Repo.get!(Delivest.Identity.Role, &1))
    |> Ecto.Changeset.change(permissions: ["orders.create"])
    |> Repo.update!()

    {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/orders/new")
    render_click(lv, "add_item", %{"product-id" => product.id})

    lv |> form("#order-details-form", order: %{customer_phone: "+7"}) |> render_submit()

    assert_redirect(lv, ~p"/staff/b/#{branch}/orders")

    assert [%Order{status: :accepted}] =
             Repo.all(Order) |> Enum.filter(&(&1.branch_id == branch.id))
  end

  test "crm order awaits successful send before acceptance", %{
    conn: conn,
    branch: branch,
    product: product,
    staff: staff
  } do
    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{
        enabled: true,
        provider: :test_crm,
        test_crm: %TestCrm.Settings{token: "t"}
      }
    })

    {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/orders/new")
    render_click(lv, "add_item", %{"product-id" => product.id})
    lv |> form("#order-details-form", order: %{customer_phone: "+7"}) |> render_submit()

    assert_redirect(lv, ~p"/staff/b/#{branch}/orders")

    assert [%Order{status: :created, crm: %{status: "pending"}} = order] =
             Repo.all(Order) |> Enum.filter(&(&1.branch_id == branch.id))

    refute Repo.get_by(OrderTransition, order_id: order.id)

    assert %Event{actor: %{"kind" => "staff", "id" => staff_id}} =
             event =
             Repo.get_by!(Event, aggregate_id: order.id, type: "order.created")

    assert staff_id == staff.id
    assert {:ok, _job} = OrderSubscriber.handle(event)
    assert_enqueued(worker: SyncWorker, args: %{"order_id" => order.id})

    assert :ok =
             perform_job(SyncWorker, %{
               "order_id" => order.id,
               "branch_id" => branch.id,
               "generation" => Delivest.Integrations.Crm.get_branch_settings(branch.id).generation
             })

    assert %Order{status: :accepted, crm: %{status: "sent"}} = Repo.reload!(order)

    assert %OrderTransition{from: :created, to: :accepted, source: :crm} =
             Repo.get_by!(OrderTransition, order_id: order.id)
  end

  test "order editor keeps queue filters for back and successful save", %{
    conn: conn,
    branch: branch,
    product: product
  } do
    query = %{period: "all", status: "created", receiving: "pickup", page: "2"}
    {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/orders/new?#{query}")

    assert has_element?(
             lv,
             "#staff-page-header a[href*='/orders?'][href*='period=all'][href*='page=2']"
           )

    render_click(lv, "add_item", %{"product-id" => product.id})

    lv |> form("#order-details-form", order: %{customer_phone: "+7"}) |> render_submit()
    assert_redirect(lv, ~p"/staff/b/#{branch}/orders?#{query}")
  end

  test "revoked order creation right blocks an open editor", %{
    conn: conn,
    branch: branch,
    product: product,
    staff: staff
  } do
    {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/orders/new")
    render_click(lv, "add_item", %{"product-id" => product.id})

    staff.role_id
    |> then(&Repo.get!(Delivest.Identity.Role, &1))
    |> Ecto.Changeset.change(permissions: ["orders.read"])
    |> Repo.update!()

    lv |> form("#order-details-form", order: %{customer_phone: "+7"}) |> render_submit()
    refute Enum.any?(Repo.all(Order), &(&1.branch_id == branch.id))
  end

  test "unsaved edits do not touch the order", %{conn: conn, branch: branch, product: product} do
    order = order_fixture(branch.id, product: product)

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/orders/#{order.id}/edit")
    render_click(lv, "add_item", %{"product-id" => product.id})

    assert Carts.get_cart_by_id(order.cart_id).total_quantity == 1
    assert [%{quantity: 1}] = Repo.preload(Repo.reload!(order), :items).items
  end

  test "edit saves the cart into the order", %{conn: conn, branch: branch, product: product} do
    order = order_fixture(branch.id, product: product)

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/orders/#{order.id}/edit")
    render_click(lv, "add_item", %{"product-id" => product.id})

    lv
    |> form("#order-details-form")
    |> render_submit()

    assert_redirect(lv, ~p"/staff/b/#{branch}/orders")
    assert [%{quantity: 2}] = Repo.preload(Repo.reload!(order), :items, force: true).items
  end

  test "an unavailable position is removed and the client is notified", %{
    conn: conn,
    branch: branch,
    product: product
  } do
    other = insert_branch_product(branch.id)
    order = order_fixture(branch.id, product: product)
    edit = ~p"/staff/b/#{branch}/orders/#{order.id}/edit"

    {:ok, lv, _html} = live(conn, edit)
    render_click(lv, "add_item", %{"product-id" => other.id})
    lv |> form("#order-details-form") |> render_submit()
    assert_redirect(lv, ~p"/staff/b/#{branch}/orders")

    assert length(Repo.preload(Repo.reload!(order), :items, force: true).items) == 2

    {:ok, lv, _html} = live(conn, edit)
    assert has_element?(lv, "#cart-item-#{product.id}")

    render_click(lv, "out_of_stock", %{"product-id" => product.id})
    refute has_element?(lv, "#cart-item-#{product.id}")
    assert render(lv) =~ "client will be notified"

    lv |> form("#order-details-form") |> render_submit()
    assert_redirect(lv, ~p"/staff/b/#{branch}/orders")

    assert [%{title: title}] = Repo.preload(Repo.reload!(order), :items, force: true).items
    assert title == other.name

    deliver_events()

    assert_enqueued(
      worker: NoteWorker,
      args: %{"order_id" => order.id, "note" => "items_removed", "titles" => [product.name]}
    )
  end

  test "the mobile cart marks a position unavailable in edit", %{
    conn: conn,
    branch: branch,
    product: product
  } do
    other = insert_branch_product(branch.id)
    order = order_fixture(branch.id, product: product)
    edit = ~p"/staff/b/#{branch}/orders/#{order.id}/edit"

    {:ok, lv, _html} = live(conn, edit)
    render_click(lv, "add_item", %{"product-id" => other.id})
    render_click(lv, "toggle_mobile_cart", %{})

    selector = "#mobile-cart-out-of-stock-#{product.id}"
    assert has_element?(lv, selector)

    render_click(lv, "out_of_stock", %{"product-id" => product.id})
    refute has_element?(lv, selector)
    assert render(lv) =~ "client will be notified"

    lv |> form("#order-details-form") |> render_submit()
    assert_redirect(lv, ~p"/staff/b/#{branch}/orders")

    assert [%{product_id: product_id}] =
             Repo.preload(Repo.reload!(order), :items, force: true).items

    assert product_id == other.id

    deliver_events()

    assert_enqueued(
      worker: NoteWorker,
      args: %{"order_id" => order.id, "note" => "items_removed", "titles" => [product.name]}
    )
  end

  test "the mobile cart has no unavailable action for a new order", %{
    conn: conn,
    branch: branch,
    product: product
  } do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/orders/new")
    render_click(lv, "add_item", %{"product-id" => product.id})
    render_click(lv, "toggle_mobile_cart", %{})

    refute has_element?(lv, "#mobile-cart-out-of-stock-#{product.id}")
  end

  test "crm orders cannot be opened for edit", %{conn: conn, branch: branch} do
    order =
      branch.id
      |> order_fixture()
      |> Delivest.Oms.Order.crm_changeset(%{provider: "frontpad"})
      |> Repo.update!()

    orders = ~p"/staff/b/#{branch}/orders"

    assert {:error, {:redirect, %{to: ^orders}}} =
             live(conn, ~p"/staff/b/#{branch}/orders/#{order.id}/edit")
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

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/orders/new")
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

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/orders/#{order.id}/edit")
    lv |> form("#order-details-form", order: %{timing: "asap"}) |> render_submit()

    assert Repo.reload!(order).cook_by == nil
  end
end
