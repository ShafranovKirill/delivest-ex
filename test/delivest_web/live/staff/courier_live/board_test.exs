defmodule DelivestWeb.Staff.CourierLive.BoardTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Couriers
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Oms.Order.Address
  alias Delivest.Repo

  setup %{conn: conn} do
    branch = insert(:branch)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      address: "Lenina 1",
      latitude: 55.75,
      longitude: 37.61,
      couriers: %{search: :manual}
    })

    operator = staff(["orders.read", "orders.update"], branch)
    courier = staff(["orders.deliver"], branch, name: "Иван", phone: "+79001112233")

    order =
      branch.id
      |> order_fixture()
      |> Ecto.Changeset.change(
        fulfillment_type: :delivery,
        status: :accepted,
        address: %Address{street: "Tverskaya", house: "7", latitude: 55.76, longitude: 37.6}
      )
      |> Repo.update!()

    {:ok, _delivery} =
      Couriers.assign(Repo.preload(operator, [:role, :branches]), order, courier.id)

    %{
      conn: init_test_session(conn, %{"staff_id" => operator.id}),
      courier_conn: init_test_session(build_conn(), %{"staff_id" => courier.id}),
      branch: branch,
      operator: operator,
      courier: courier,
      order: order
    }
  end

  defp staff(permissions, branch, attrs \\ []) do
    staff = insert(:staff, Keyword.merge([role: build(:role, permissions: permissions)], attrs))
    insert(:staff_branch, staff: staff, branch: branch)
    staff
  end

  defp eventually(fun, attempts \\ 50) do
    if fun.() or attempts == 0 do
      assert fun.()
    else
      Process.sleep(20)
      eventually(fun, attempts - 1)
    end
  end

  test "a courier with the page open shows up on the map with the orders", ctx do
    {:ok, board, _html} = live(ctx.conn, ~p"/staff/b/#{ctx.branch}/couriers")
    assert board |> element("#courier-#{ctx.courier.id}-status") |> render() =~ "offline"
    assert has_element?(board, "#courier-#{ctx.courier.id}-order-#{ctx.order.id}")

    {:ok, courier_page, _html} = live(ctx.courier_conn, ~p"/staff/b/#{ctx.branch}/deliveries")
    render_hook(courier_page, "location", %{"lat" => 55.7601, "lng" => 37.6012})

    eventually(fn -> has_element?(board, "#courier-#{ctx.courier.id}-age") end)
    assert board |> element("#courier-#{ctx.courier.id}-status") |> render() =~ "online"
    assert_push_event(board, "courier_positions", %{positions: [%{lat: 55.7601, name: "Иван"}]})
  end

  test "a broken location is ignored", ctx do
    {:ok, courier_page, _html} = live(ctx.courier_conn, ~p"/staff/b/#{ctx.branch}/deliveries")
    render_hook(courier_page, "location", %{"lat" => 200, "lng" => "x"})

    assert DelivestWeb.CourierPresence.positions(ctx.branch.id, [ctx.courier]) == []
  end

  test "the operator sees the courier in the open order card", ctx do
    {:ok, courier_page, _html} = live(ctx.courier_conn, ~p"/staff/b/#{ctx.branch}/deliveries")
    render_hook(courier_page, "location", %{"lat" => 55.7601, "lng" => 37.6012})

    {:ok, lv, _html} = live(ctx.conn, ~p"/staff/b/#{ctx.branch}/orders?id=#{ctx.order.id}")

    assert has_element?(
             lv,
             "#order-courier-map-#{ctx.order.id}[data-courier-id='#{ctx.courier.id}']"
           )

    assert lv |> element("#order-courier-location-#{ctx.order.id}") |> render() =~ "just now"
  end

  test "the operator accepts the cash", ctx do
    courier = Repo.preload(ctx.courier, [:role, :branches])
    operator = Repo.preload(ctx.operator, [:role, :branches])
    delivery = Couriers.active(ctx.order.id)

    {:ok, order} = Delivest.Oms.Orders.advance_order(ctx.order, :preparing, {:staff, operator})
    {:ok, _order} = Delivest.Oms.Orders.advance_order(order, :ready, {:staff, operator})
    {:ok, _order} = Couriers.pick_up(courier, ctx.branch.id, delivery.id)
    {:ok, _order} = Couriers.hand_over(courier, ctx.branch.id, delivery.id)

    {:ok, board, _html} = live(ctx.conn, ~p"/staff/b/#{ctx.branch}/couriers")
    assert board |> element("#courier-#{ctx.courier.id}-cash") |> render() =~ "150"

    board |> element("#settle-#{ctx.courier.id}") |> render_click()

    refute has_element?(board, "#courier-#{ctx.courier.id}-cash")
    assert render(board) =~ "Accepted 150"
  end

  test "a courier cannot open the board", ctx do
    assert {:error, {:redirect, _}} = live(ctx.courier_conn, ~p"/staff/b/#{ctx.branch}/couriers")
  end
end
