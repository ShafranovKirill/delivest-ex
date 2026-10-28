defmodule Delivest.Oms.OrderFlowTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Identity.{Branch, Role, Staff}
  alias Delivest.Oms.{Order, OrderFlow, Orders, OrderTransition}

  @branch_id Ecto.UUID.generate()

  defp staff(permissions),
    do: %Staff{role: %Role{permissions: permissions}, branches: [%Branch{id: @branch_id}]}

  defp order(status, attrs \\ []),
    do: struct(%Order{status: status, fulfillment_type: :pickup, branch_id: @branch_id}, attrs)

  describe "path" do
    test "only orders with a courier leg go through delivering" do
      refute :delivering in OrderFlow.path(order(:ready))
      assert :delivering in OrderFlow.path(order(:ready, fulfillment_type: :delivery))
      assert :delivering in OrderFlow.path(order(:ready, channel: %{delivery: "yandex"}))
    end

    test "next follows the path of the order" do
      assert OrderFlow.next(order(:ready)) == :completed
      assert OrderFlow.next(order(:ready, fulfillment_type: :delivery)) == :delivering
      assert OrderFlow.next(order(:completed)) == nil
    end
  end

  describe "staff" do
    test "moves one step at a time and never back" do
      operator = {:staff, staff(["orders.update"])}

      assert {:ok, [{:created, :accepted}]} =
               OrderFlow.steps(order(:created), :accepted, operator)

      assert {:error, :skipped_step} = OrderFlow.steps(order(:created), :ready, operator)
      assert {:error, :backward} = OrderFlow.steps(order(:ready), :preparing, operator)
      assert {:error, :finished} = OrderFlow.steps(order(:completed), :cancelled, operator)
      assert {:error, :unreachable} = OrderFlow.steps(order(:ready), :delivering, operator)
    end

    test "the cook takes only kitchen steps" do
      cook = {:staff, staff(["orders.cook"])}

      assert OrderFlow.can?(order(:accepted), :preparing, cook)
      assert OrderFlow.can?(order(:preparing), :ready, cook)
      refute OrderFlow.can?(order(:created), :accepted, cook)
      refute OrderFlow.can?(order(:ready), :completed, cook)
      refute OrderFlow.can?(order(:preparing), :cancelled, cook)
    end

    test "staff of another branch and crm orders are refused" do
      stranger = {:staff, %Staff{staff(["orders.update"]) | branches: []}}
      admin = {:staff, staff(["admin"])}

      assert {:error, :forbidden} = OrderFlow.steps(order(:created), :accepted, stranger)

      assert {:error, :order_locked} =
               OrderFlow.steps(order(:created, crm: %{provider: "frontpad"}), :accepted, admin)
    end
  end

  describe "external sources" do
    test "leap over steps and ignore what is behind" do
      assert {:ok, [{:created, :accepted}, {:accepted, :preparing}, {:preparing, :ready}]} =
               OrderFlow.steps(order(:created), :ready, :crm)

      assert {:ignored, :backward} = OrderFlow.steps(order(:ready), :accepted, :crm)
      assert {:ignored, :finished} = OrderFlow.steps(order(:cancelled), :completed, :channel)
    end

    test "a courier status of an order without a courier means ready" do
      assert {:ok, [{:preparing, :ready}]} = OrderFlow.steps(order(:preparing), :delivering, :crm)
    end
  end

  test "the courier only carries delivery orders" do
    courier = {:courier, staff([])}
    delivery = order(:ready, fulfillment_type: :delivery)

    assert OrderFlow.can?(delivery, :delivering, courier)
    refute OrderFlow.can?(delivery, :cancelled, courier)
    refute OrderFlow.can?(order(:ready), :completed, courier)
  end

  describe "transitions" do
    setup do
      branch = insert(:branch)
      admin = insert(:staff, role: build(:role, permissions: ["admin"]))
      %{order: order_fixture(branch.id), admin: admin}
    end

    defp transitions(order),
      do: Repo.all(from(t in OrderTransition, where: t.order_id == ^order.id, order_by: t.id))

    test "each step is written with its source and staff", %{order: order, admin: admin} do
      {:ok, order} = Orders.advance_order(order, :accepted, {:staff, admin})
      {:ok, _order} = Orders.advance_order(order, :completed, :system)

      assert [
               %{from: :created, to: :accepted, source: :staff, staff_id: staff_id},
               %{from: :accepted, to: :preparing, source: :system, staff_id: nil},
               %{from: :preparing, to: :ready, source: :system},
               %{from: :ready, to: :completed, source: :system}
             ] = transitions(order)

      assert staff_id == admin.id
    end

    test "a revert takes the last step back once per step", %{order: order, admin: admin} do
      {:ok, order} = Orders.advance_order(order, :accepted, :system)

      assert {:error, :forbidden} =
               Orders.revert_order_status(order, insert(:staff), "Ошибка")

      assert {:ok, %{status: :created} = order} =
               Orders.revert_order_status(order, admin, "Ошибка")

      assert [%{reverted_at: %DateTime{}, revert_reason: "Ошибка"}] = transitions(order)
      assert {:error, :nothing_to_revert} = Orders.revert_order_status(order, admin, "Ещё")
    end

    test "a cancel by the channel waits for an operator", %{order: order, admin: admin} do
      {:ok, order} = Orders.cancel_order(order, :channel, %{"cancel_reason" => "other"})
      assert [%{id: id}] = Orders.list_unacknowledged_cancellations(order.branch_id)
      assert id == order.id

      {:ok, _order} = Orders.acknowledge_cancel(order, admin)
      assert [] = Orders.list_unacknowledged_cancellations(order.branch_id)
    end

    test "a cancel by staff raises no alarm", %{order: order, admin: admin} do
      {:ok, order} = Orders.cancel_order(order, {:staff, admin}, %{"cancel_reason" => "other"})
      assert [] = Orders.list_unacknowledged_cancellations(order.branch_id)
    end

    test "an order can be created already advanced", %{order: order} do
      {:ok, cart} = Delivest.Oms.Carts.create_cart(%{branch_id: order.branch_id})
      product = insert_branch_product(order.branch_id, price: 100)
      {:ok, _, _} = Delivest.Oms.Carts.add_item(cart.id, product.id, 1)

      {:ok, created} =
        Orders.create_order(
          %{"cart_id" => cart.id, "fulfillment_type" => "pickup", "payment_method" => "cash"},
          advance: {:accepted, :channel}
        )

      assert created.status == :accepted
      assert [%{from: :created, to: :accepted, source: :channel}] = transitions(created)
    end
  end
end
