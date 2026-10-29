defmodule Delivest.Couriers.CashTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Couriers
  alias Delivest.Couriers.Settlement
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Oms.Orders

  setup do
    branch = insert(:branch)
    Repo.insert!(%BranchInfo{branch_id: branch.id, couriers: %{}})

    %{
      branch: branch,
      operator: staff(["orders.update"], branch),
      courier: staff(["orders.deliver"], branch)
    }
  end

  defp staff(permissions, branch) do
    insert(:staff, role: build(:role, permissions: permissions), branches: [branch])
    |> Repo.preload([:role, :branches])
  end

  defp delivered(ctx, payment_method, price) do
    order =
      ctx.branch.id
      |> order_fixture(price: price)
      |> Ecto.Changeset.change(fulfillment_type: :delivery, payment_method: payment_method)
      |> Repo.update!()

    order =
      Enum.reduce([:accepted, :preparing], order, fn to, order ->
        {:ok, order} = Orders.advance_order(order, to, {:staff, ctx.operator})
        order
      end)

    delivery = Couriers.active(order.id)
    {:ok, _} = Couriers.take(ctx.courier, ctx.branch.id, delivery.id)
    {:ok, _} = Orders.advance_order(Repo.reload!(order), :ready, {:staff, ctx.operator})
    {:ok, _} = Couriers.pick_up(ctx.courier, ctx.branch.id, delivery.id)
    {:ok, _} = Couriers.hand_over(ctx.courier, ctx.branch.id, delivery.id)
  end

  test "the courier owes the cash and the terminal of handed orders", ctx do
    delivered(ctx, :cash, 500)
    delivered(ctx, :cash, 300)
    delivered(ctx, :card_offline, 700)
    delivered(ctx, :online, 900)

    assert %{cash: 800, card: 700, orders: 3} =
             Couriers.balance(ctx.branch.id, ctx.courier.id)
  end

  test "the operator accepts the cash and the count starts over", ctx do
    delivered(ctx, :cash, 500)
    Couriers.subscribe(ctx.branch.id)

    assert {:ok, %Settlement{cash_amount: 500, card_amount: 0, orders_count: 1}} =
             Couriers.settle(ctx.operator, ctx.branch.id, ctx.courier.id)

    assert_receive {:deliveries_changed, _branch_id}
    assert %{cash: 0, orders: 0} = Couriers.balance(ctx.branch.id, ctx.courier.id)

    assert {:error, :nothing_to_settle} =
             Couriers.settle(ctx.operator, ctx.branch.id, ctx.courier.id)

    delivered(ctx, :cash, 200)
    assert %{cash: 200, orders: 1} = Couriers.balance(ctx.branch.id, ctx.courier.id)
  end

  test "a courier cannot accept the cash", ctx do
    delivered(ctx, :cash, 500)

    assert {:error, :forbidden} = Couriers.settle(ctx.courier, ctx.branch.id, ctx.courier.id)
  end
end
