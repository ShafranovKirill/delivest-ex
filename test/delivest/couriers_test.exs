defmodule Delivest.CouriersTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Couriers
  alias Delivest.Couriers.Delivery
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Oms.{Order, Orders, OrderTransition}

  defp branch(couriers \\ %{}) do
    branch = insert(:branch)
    Repo.insert!(%BranchInfo{branch_id: branch.id, couriers: couriers})
    branch
  end

  defp staff(permissions, branch) do
    insert(:staff, role: build(:role, permissions: permissions), branches: [branch])
    |> Repo.preload([:role, :branches])
  end

  defp courier(branch), do: staff(["orders.deliver"], branch)
  defp operator(branch), do: staff(["orders.update"], branch)

  defp order(branch, changes \\ []) do
    branch.id
    |> order_fixture()
    |> Ecto.Changeset.change(Keyword.merge([fulfillment_type: :delivery], changes))
    |> Repo.update!()
  end

  defp advance(order, statuses, operator) do
    Enum.reduce(statuses, order, fn to, order ->
      {:ok, order} = Orders.advance_order(order, to, {:staff, operator})
      order
    end)
  end

  defp deliveries(order) do
    Delivery
    |> where([d], d.order_id == ^order.id)
    |> order_by([d], asc: d.inserted_at)
    |> Repo.all()
    |> Enum.map(&{&1.status, &1.close_reason})
  end

  describe "starting the search" do
    test "starts when cooking begins by default" do
      branch = branch()
      order = order(branch)
      advance(order, [:accepted], operator(branch))
      assert deliveries(order) == []

      advance(Repo.reload!(order), [:preparing], operator(branch))
      assert [{:searching, nil}] = deliveries(order)
      assert %Delivery{provider: :staff} = Couriers.active(order.id)
    end

    test "waits for the ready order when the branch says so" do
      branch = branch(%{search: :ready})
      order = order(branch)
      advance(order, [:accepted, :preparing], operator(branch))
      assert deliveries(order) == []

      advance(Repo.reload!(order), [:ready], operator(branch))
      assert [{:searching, nil}] = deliveries(order)
    end

    test "manual search waits for the operator button" do
      branch = branch(%{search: :manual})
      operator = operator(branch)
      order = order(branch) |> advance([:accepted, :preparing, :ready], operator)
      assert deliveries(order) == []

      assert {:ok, %Delivery{status: :searching}} = Couriers.find(operator, order)
      assert {:error, :already_searching} = Couriers.find(operator, order)
    end

    test "pickup orders and frontpad branches get no courier" do
      branch = branch()
      pickup = order(branch, fulfillment_type: :pickup)
      advance(pickup, [:accepted, :preparing], operator(branch))
      assert deliveries(pickup) == []

      frontpad = insert(:branch)

      Repo.insert!(%BranchInfo{
        branch_id: frontpad.id,
        crm: %{enabled: true, provider: :frontpad, frontpad: %{api_key: "key"}}
      })

      assert Couriers.settings(frontpad.id) == nil
      order = order(frontpad, status: :accepted)
      assert {:error, :not_available} = Couriers.find(operator(frontpad), order)
    end
  end

  describe "couriers" do
    setup do
      branch = branch()
      order = order(branch) |> advance([:accepted, :preparing], operator(branch))
      %{branch: branch, order: order, delivery: Couriers.active(order.id)}
    end

    test "the first courier takes the request, the others lose it", ctx do
      first = courier(ctx.branch)
      second = courier(ctx.branch)
      Couriers.subscribe(ctx.branch.id)

      assert [%Delivery{}] = Couriers.list_open(ctx.branch.id)

      assert {:ok, %Delivery{status: :assigned}} =
               Couriers.take(first, ctx.branch.id, ctx.delivery.id)

      assert_receive {:deliveries_changed, _branch_id}
      assert {:error, :taken} = Couriers.take(second, ctx.branch.id, ctx.delivery.id)

      assert Couriers.list_open(ctx.branch.id) == []
      assert [%Delivery{order: %Order{}}] = Couriers.list_mine(first, ctx.branch.id)
      assert Couriers.list_mine(second, ctx.branch.id) == []
    end

    test "a courier of another branch cannot take it", ctx do
      stranger = courier(insert(:branch))
      assert {:error, :forbidden} = Couriers.take(stranger, ctx.branch.id, ctx.delivery.id)
    end

    test "refusing sends the order back to the search", ctx do
      courier = courier(ctx.branch)
      {:ok, _delivery} = Couriers.take(courier, ctx.branch.id, ctx.delivery.id)

      assert {:ok, %Delivery{status: :searching}} =
               Couriers.refuse(courier, ctx.branch.id, ctx.delivery.id)

      assert deliveries(ctx.order) == [{:failed, :refused}, {:searching, nil}]
      assert Repo.reload!(ctx.order).status == :preparing
    end

    test "picked up and handed over move the order", ctx do
      courier = courier(ctx.branch)
      other = courier(ctx.branch)
      {:ok, _delivery} = Couriers.take(courier, ctx.branch.id, ctx.delivery.id)

      assert {:error, :not_ready} = Couriers.pick_up(courier, ctx.branch.id, ctx.delivery.id)

      advance(ctx.order, [:ready], operator(ctx.branch))
      assert {:error, :not_yours} = Couriers.pick_up(other, ctx.branch.id, ctx.delivery.id)

      assert {:ok, %Order{status: :delivering}} =
               Couriers.pick_up(courier, ctx.branch.id, ctx.delivery.id)

      assert [{:picked_up, nil}] = deliveries(ctx.order)
      assert {:error, :not_yours} = Couriers.refuse(courier, ctx.branch.id, ctx.delivery.id)

      assert {:ok, %Order{status: :completed}} =
               Couriers.hand_over(courier, ctx.branch.id, ctx.delivery.id)

      assert [{:delivered, nil}] = deliveries(ctx.order)

      assert [
               {:ready, :delivering, :courier, id},
               {:delivering, :completed, :courier, id}
             ] =
               OrderTransition
               |> where([t], t.order_id == ^ctx.order.id and t.source == :courier)
               |> order_by(asc: :id)
               |> select([t], {t.from, t.to, t.source, t.staff_id})
               |> Repo.all()

      assert id == courier.id
    end

    test "cancelling the order cancels the search", ctx do
      {:ok, _order} =
        Orders.cancel_order(ctx.order, {:staff, operator(ctx.branch)}, %{
          "cancel_reason" => "other"
        })

      assert deliveries(ctx.order) == [{:cancelled, :order_cancelled}]
    end

    test "the operator hands the order over without the courier", ctx do
      advance(ctx.order, [:ready, :delivering], operator(ctx.branch))
      assert deliveries(ctx.order) == [{:cancelled, :handed_over}]
    end
  end

  describe "operator assignment" do
    test "assigns, replaces and removes a courier before pickup" do
      branch = branch(%{search: :manual})
      operator = operator(branch)
      first = courier(branch)
      second = courier(branch)
      order = order(branch) |> advance([:accepted], operator)

      assert {:ok, %Delivery{status: :assigned, courier_id: id, assigned_by_id: by}} =
               Couriers.assign(operator, order, first.id)

      assert {id, by} == {first.id, operator.id}
      assert {:ok, _delivery} = Couriers.assign(operator, order, first.id)
      assert [{:assigned, nil}] = deliveries(order)

      assert {:ok, %Delivery{courier_id: id}} = Couriers.assign(operator, order, second.id)
      assert id == second.id
      assert deliveries(order) == [{:failed, :reassigned}, {:assigned, nil}]

      assert {:ok, %Delivery{status: :searching}} = Couriers.unassign(operator, order)
      assert {:error, :not_assigned} = Couriers.unassign(operator, order)

      {:ok, %Delivery{status: :assigned}} = Couriers.assign(operator, order, first.id)
      assert length(deliveries(order)) == 3
    end

    test "only couriers of the branch can be assigned" do
      branch = branch(%{search: :manual})
      operator = operator(branch)
      order = order(branch) |> advance([:accepted], operator)
      courier = courier(branch)
      cook = staff(["orders.cook"], branch)
      outsider = courier(insert(:branch))

      assert {:error, :not_a_courier} = Couriers.assign(operator, order, cook.id)
      assert {:error, :not_a_courier} = Couriers.assign(operator, order, outsider.id)
      assert [%{id: id}] = Couriers.list_couriers(branch.id)
      assert id == courier.id
    end
  end
end
