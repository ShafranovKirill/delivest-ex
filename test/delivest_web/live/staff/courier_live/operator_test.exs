defmodule DelivestWeb.Staff.CourierLive.OperatorTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Couriers
  alias Delivest.Couriers.Delivery
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Repo

  setup %{conn: conn} do
    branch = insert(:branch)
    Repo.insert!(%BranchInfo{branch_id: branch.id, couriers: %{search: :manual}})
    operator = staff(["orders.read", "orders.update"], branch)
    courier = staff(["orders.deliver"], branch)

    order =
      branch.id
      |> order_fixture()
      |> Ecto.Changeset.change(fulfillment_type: :delivery, status: :accepted)
      |> Repo.update!()

    %{
      conn: init_test_session(conn, %{"staff_id" => operator.id}),
      branch: branch,
      courier: courier,
      order: order
    }
  end

  defp staff(permissions, branch) do
    staff = insert(:staff, role: build(:role, permissions: permissions))
    insert(:staff_branch, staff: staff, branch: branch)
    staff
  end

  defp orders_page(conn, branch), do: live(conn, ~p"/staff/b/#{branch}/orders")

  test "the operator starts the search and a courier taking it shows up", ctx do
    {:ok, lv, _html} = orders_page(ctx.conn, ctx.branch)
    assert lv |> element("#order-delivery-state-#{ctx.order.id}") |> render() =~ "No courier yet"

    lv |> element("#order-find-courier-#{ctx.order.id}") |> render_click()
    assert lv |> element("#order-delivery-state-#{ctx.order.id}") |> render() =~ "Looking for"
    refute has_element?(lv, "#order-find-courier-#{ctx.order.id}")

    courier = Repo.preload(ctx.courier, [:role, :branches])
    delivery = Couriers.active(ctx.order.id)
    {:ok, _delivery} = Couriers.take(courier, ctx.branch.id, delivery.id)

    assert lv |> element("#order-delivery-state-#{ctx.order.id}") |> render() =~
             "Courier assigned"
  end

  test "the operator assigns and removes a courier", ctx do
    {:ok, lv, _html} = orders_page(ctx.conn, ctx.branch)

    lv
    |> form("#order-assign-courier-#{ctx.order.id}", %{courier_id: ctx.courier.id})
    |> render_change()

    assert %Delivery{status: :assigned, courier_id: id} = Couriers.active(ctx.order.id)
    assert id == ctx.courier.id
    assert lv |> element("#order-delivery-panel-#{ctx.order.id}") |> render() =~ ctx.courier.login

    lv |> element("#order-unassign-courier-#{ctx.order.id}") |> render_click()
    assert %Delivery{status: :searching} = Couriers.active(ctx.order.id)
  end

  test "an order picked up by the courier has no revert button", ctx do
    admin = staff(["orders.read", "orders.update", "orders.revert"], ctx.branch)
    conn = init_test_session(build_conn(), %{"staff_id" => admin.id})
    courier = Repo.preload(ctx.courier, [:role, :branches])
    admin = Repo.preload(admin, [:role, :branches])

    {:ok, order} = Delivest.Oms.Orders.advance_order(ctx.order, :preparing, {:staff, admin})
    {:ok, _delivery} = Couriers.find(admin, order)
    {:ok, _delivery} = Couriers.assign(admin, order, courier.id)

    {:ok, lv, _html} = orders_page(conn, ctx.branch)
    assert has_element?(lv, "#order-revert-#{order.id}")

    {:ok, order} = Delivest.Oms.Orders.advance_order(order, :ready, {:staff, admin})
    {:ok, _order} = Couriers.pick_up(courier, ctx.branch.id, Couriers.active(order.id).id)

    {:ok, lv, _html} = orders_page(conn, ctx.branch)
    assert has_element?(lv, "#order-status-#{order.id}", "Delivering")
    refute has_element?(lv, "#order-revert-#{order.id}")
  end

  test "pickup orders have no courier panel", ctx do
    pickup =
      ctx.branch.id
      |> order_fixture()
      |> Ecto.Changeset.change(status: :accepted)
      |> Repo.update!()

    {:ok, lv, _html} = orders_page(ctx.conn, ctx.branch)
    refute has_element?(lv, "#order-delivery-panel-#{pickup.id}")
  end
end
