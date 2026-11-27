defmodule Delivest.CouriersTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Couriers
  alias Delivest.Couriers.Delivery
  alias Delivest.Features
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Oms.{Order, Orders, OrderTransition}

  defp branch(couriers \\ %{}) do
    branch = insert(:branch)
    Repo.insert!(%BranchInfo{branch_id: branch.id, couriers: couriers})
    enable_own_couriers(branch)
    branch
  end

  defp enable_own_couriers(branch) do
    {:ok, _} = Features.configure("couriers", :franchise, true, actor: "test")
    {:ok, _} = Features.configure("couriers", {:branch, branch.id}, true, actor: "test")
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
      deliver_events()
      Repo.reload!(order)
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
    test "a newly created branch has own couriers off until enabled" do
      branch = insert(:branch)
      Repo.insert!(%BranchInfo{branch_id: branch.id})
      refute Couriers.own_enabled?(branch.id)

      order = order(branch)
      advance(order, [:accepted, :preparing], operator(branch))
      assert deliveries(order) == []
    end

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

    test "new staff search is announced after its database commit" do
      branch = branch(%{search: :manual})
      operator = operator(branch)
      order = order(branch) |> advance([:accepted], operator)
      Couriers.subscribe(branch.id)

      test_pid = self()
      handler = "courier-search-commit-#{System.unique_integer([:positive])}"

      :ok =
        :telemetry.attach(
          handler,
          [:delivest, :repo, :query],
          fn _, _, metadata, _ ->
            if self() == test_pid and String.downcase(metadata.query || "") == "commit",
              do: send(test_pid, :courier_search_committed)
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(handler) end)
      assert {:ok, %Delivery{status: :searching}} = Couriers.find(operator, order)

      receive do
        :courier_search_committed -> :ok
        {:deliveries_changed, _} -> flunk("courier search was announced before commit")
      after
        1_000 -> flunk("courier search commit was not observed")
      end

      assert_receive {:deliveries_changed, branch_id}
      assert branch_id == branch.id
      assert %Delivery{status: :searching} = Couriers.active(order.id)
    end

    test "pickup orders get no courier" do
      branch = branch()
      pickup = order(branch, fulfillment_type: :pickup)
      advance(pickup, [:accepted, :preparing], operator(branch))
      assert deliveries(pickup) == []
    end

    test "a frontpad branch searches only when the operator asks and only outside the crm" do
      frontpad = insert(:branch) |> enable_own_couriers()

      Repo.insert!(%BranchInfo{
        branch_id: frontpad.id,
        crm: %{enabled: true, provider: :frontpad, frontpad: %{api_key: "key"}}
      })

      operator = operator(frontpad)
      order = order(frontpad) |> advance([:accepted, :preparing], operator)
      assert deliveries(order) == []

      assert {:ok, %Delivery{status: :searching}} = Couriers.find(operator, Repo.reload!(order))

      in_crm =
        order(frontpad,
          status: :accepted,
          crm: %Order.CrmSync{provider: "frontpad", status: "sent"}
        )

      assert {:error, :not_available} = Couriers.find(operator, in_crm)
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

    test "turning off own couriers stops new assignments but preserves an active delivery", ctx do
      first = courier(ctx.branch)
      second = courier(ctx.branch)
      {:ok, assigned} = Couriers.take(first, ctx.branch.id, ctx.delivery.id)
      assert Couriers.active_for_staff?(first, ctx.branch.id)

      {:ok, _} = Features.configure("couriers", {:branch, ctx.branch.id}, false, actor: "test")
      refute Couriers.own_enabled?(ctx.branch.id)
      assert Couriers.list_open(ctx.branch.id) == []
      assert {:error, :disabled} = Couriers.take(second, ctx.branch.id, assigned.id)
      assert [%Delivery{id: id}] = Couriers.list_mine(first, ctx.branch.id)
      assert id == assigned.id

      assert {:ok, _closed} = Couriers.refuse(first, ctx.branch.id, assigned.id)
      refute Couriers.active_for_staff?(first, ctx.branch.id)
      assert deliveries(ctx.order) == [{:failed, :refused}]
    end

    test "a courier can finish a previously assigned delivery while the feature is off", ctx do
      courier = courier(ctx.branch)
      {:ok, delivery} = Couriers.take(courier, ctx.branch.id, ctx.delivery.id)
      {:ok, _} = Features.configure("couriers", {:branch, ctx.branch.id}, false, actor: "test")

      advance(Repo.reload!(ctx.order), [:ready], operator(ctx.branch))
      assert {:ok, _order} = Couriers.pick_up(courier, ctx.branch.id, delivery.id)
      assert {:ok, _order} = Couriers.hand_over(courier, ctx.branch.id, delivery.id)
      assert deliveries(ctx.order) == [{:delivered, nil}]
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

      deliver_events()

      assert [{:picked_up, nil}] = deliveries(ctx.order)
      assert {:error, :not_yours} = Couriers.refuse(courier, ctx.branch.id, ctx.delivery.id)

      assert {:ok, %Order{status: :completed}} =
               Couriers.hand_over(courier, ctx.branch.id, ctx.delivery.id)

      deliver_events()

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

      deliver_events()
      assert deliveries(ctx.order) == [{:cancelled, :order_cancelled}]
    end

    test "the operator confirms an active delivery with a reason", ctx do
      operator = operator(ctx.branch)
      order = advance(ctx.order, [:ready], operator)

      assert {:error, :delivery_changed} =
               Orders.advance_order(order, :delivering, {:staff, operator})

      assert {:error, :delivery_reason_required} =
               Orders.advance_order(order, :delivering, {:staff, operator},
                 delivery_id: ctx.delivery.id,
                 reason: "  "
               )

      assert {:ok, %Order{status: :delivering}} =
               Orders.advance_order(order, :delivering, {:staff, operator},
                 delivery_id: ctx.delivery.id,
                 reason: "  Забрал другой курьер  "
               )

      assert %Delivery{status: :picked_up} = Repo.reload!(ctx.delivery)

      assert %OrderTransition{staff_id: id, reason: "Забрал другой курьер"} =
               Repo.get_by!(OrderTransition, order_id: order.id, to: :delivering)

      assert id == operator.id

      assert {:error, :delivery_reason_required} =
               Orders.advance_order(Repo.reload!(order), :completed, {:staff, operator},
                 delivery_id: ctx.delivery.id,
                 reason: ""
               )

      assert {:ok, %Order{status: :completed}} =
               Orders.advance_order(Repo.reload!(order), :completed, {:staff, operator},
                 delivery_id: ctx.delivery.id,
                 reason: "Вручено клиенту"
               )

      assert %Delivery{status: :delivered} = Repo.reload!(ctx.delivery)

      assert Repo.get_by!(OrderTransition, order_id: order.id, to: :completed).reason ==
               "Вручено клиенту"
    end

    test "a stale manual confirmation cannot act on a new attempt", ctx do
      operator = operator(ctx.branch)
      order = advance(ctx.order, [:ready], operator)
      assert {:ok, _} = Couriers.take(courier(ctx.branch), ctx.branch.id, ctx.delivery.id)
      assert {:ok, _} = Couriers.unassign(operator, order)
      deliver_events()

      assert {:error, :delivery_changed} =
               Orders.advance_order(Repo.reload!(order), :delivering, {:staff, operator},
                 delivery_id: ctx.delivery.id,
                 reason: "Забрал"
               )

      assert Repo.reload!(order).status == :ready
    end
  end

  describe "revert" do
    test "is allowed until the courier picks the order up" do
      branch = branch()
      admin = staff(["orders.update", "orders.revert"], branch)
      courier = courier(branch)
      order = order(branch) |> advance([:accepted, :preparing, :ready], admin)
      delivery = Couriers.active(order.id)
      {:ok, _delivery} = Couriers.take(courier, branch.id, delivery.id)

      assert {:ok, %Order{status: :preparing}} =
               Orders.revert_order_status(Repo.reload!(order), admin, "too early")

      advance(Repo.reload!(order), [:ready], admin)
      {:ok, _order} = Couriers.pick_up(courier, branch.id, delivery.id)
      deliver_events()

      assert {:error, :handed_to_courier} =
               Orders.revert_order_status(Repo.reload!(order), admin, "mistake")

      {:ok, _order} = Couriers.hand_over(courier, branch.id, delivery.id)
      deliver_events()

      assert {:error, :handed_to_courier} =
               Orders.revert_order_status(Repo.reload!(order), admin, "mistake")

      assert Repo.reload!(order).status == :completed
    end
  end

  describe "operator assignment" do
    test "unassigning while disabled closes the existing assignment without searching again" do
      branch = branch(%{search: :manual})
      operator = operator(branch)
      courier = courier(branch)
      order = order(branch) |> advance([:accepted], operator)
      {:ok, _delivery} = Couriers.assign(operator, order, courier.id)
      {:ok, _} = Features.configure("couriers", {:branch, branch.id}, false, actor: "test")

      assert {:ok, _closed} = Couriers.unassign(operator, order)
      assert deliveries(order) == [{:failed, :unassigned}]
    end

    test "disabled own couriers block manual search and assignment" do
      branch = branch(%{search: :manual})
      operator = operator(branch)
      courier = courier(branch)
      order = order(branch) |> advance([:accepted], operator)
      {:ok, _} = Features.configure("couriers", {:branch, branch.id}, false, actor: "test")

      assert {:error, :disabled} = Couriers.find(operator, order)
      assert {:error, :disabled} = Couriers.assign(operator, order, courier.id)
      assert deliveries(order) == []
    end

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
