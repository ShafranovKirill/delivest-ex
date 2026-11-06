defmodule Delivest.Couriers.CashTest do
  use Delivest.DataCase, async: false

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Couriers
  alias Delivest.Couriers.Settlement
  alias Delivest.Audit.Event
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Oms.{Cart, Order, Orders}
  alias Delivest.Payments.Payment

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

    {:ok, _payments} = Delivest.Payments.sync(Repo, order)

    order =
      Enum.reduce([:accepted, :preparing], order, fn to, order ->
        {:ok, order} = Orders.advance_order(order, to, {:staff, ctx.operator})
        order
      end)

    deliver_events()

    delivery = Couriers.active(order.id)
    {:ok, _} = Couriers.take(ctx.courier, ctx.branch.id, delivery.id)
    {:ok, _} = Orders.advance_order(Repo.reload!(order), :ready, {:staff, ctx.operator})
    {:ok, _} = Couriers.pick_up(ctx.courier, ctx.branch.id, delivery.id)
    deliver_events()
    {:ok, _} = Couriers.hand_over(ctx.courier, ctx.branch.id, delivery.id)
    deliver_events()
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

  test "two independent database connections settle a payment only once" do
    {operator, branch, courier, order, cart} =
      Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
        branch = insert(:branch)
        operator = independent_staff(["orders.update"], branch)
        courier = independent_staff(["orders.deliver"], branch)
        cart = Repo.insert!(%Cart{branch_id: branch.id})

        order =
          Repo.insert!(%Order{
            branch_id: branch.id,
            cart_id: cart.id,
            number: "cash-concurrency-#{Ecto.UUID.generate()}",
            business_date: Date.utc_today(),
            daily_number: 1,
            total_amount: 500
          })

        Repo.insert!(%Payment{
          order_id: order.id,
          branch_id: branch.id,
          method: :cash,
          amount: 500,
          status: :paid,
          collected_by_id: courier.id,
          paid_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

        {operator, branch, courier, order, cart}
      end)

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
        Repo.delete_all(from(e in Event, where: e.actor_id == ^operator.id))
        Repo.delete!(order)
        Repo.delete!(cart)
        Repo.delete!(branch)
        Repo.delete!(operator)
        Repo.delete!(courier)
        Repo.delete!(operator.role)
        Repo.delete!(courier.role)
      end)
    end)

    parent = self()

    tasks =
      Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
        Repo.transaction(fn ->
          Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1), hashtext($2))", [
            "courier_cash_settlement",
            "#{branch.id}:#{courier.id}"
          ])

          tasks =
            for _ <- 1..2 do
              Task.async(fn ->
                Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
                  %{rows: [[backend_pid]]} = Repo.query!("SELECT pg_backend_pid()")
                  send(parent, {:ready_to_settle, self(), backend_pid})
                  receive do: (:settle -> :ok)
                  Delivest.Couriers.Cash.settle(operator, branch.id, courier.id)
                end)
              end)
            end

          pids =
            for _ <- tasks do
              assert_receive {:ready_to_settle, task_pid, backend_pid}
              send(task_pid, :settle)
              backend_pid
            end

          assert_advisory_wait(pids)
          tasks
        end)
        |> elem(1)
      end)

    results = Enum.map(tasks, &Task.await(&1, 15_000))

    assert Enum.count(results, &match?({:ok, %Settlement{}}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :nothing_to_settle})) == 1

    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      assert Repo.aggregate(from(s in Settlement, where: s.branch_id == ^branch.id), :count, :id) ==
               1

      assert [payment] = Repo.all(from(p in Payment, where: p.branch_id == ^branch.id))
      assert payment.settlement_id == elem(Enum.find(results, &match?({:ok, _}, &1)), 1).id
    end)
  end

  defp independent_staff(permissions, branch) do
    role =
      build(:role,
        name: "CashConcurrency_#{System.unique_integer([:positive])}",
        permissions: permissions
      )

    insert(:staff, role: role, branches: [branch])
    |> Repo.preload([:role, :branches])
  end

  defp assert_advisory_wait(pids, attempts \\ 100)

  defp assert_advisory_wait(_pids, 0),
    do: flunk("both settlements did not wait on the advisory lock")

  defp assert_advisory_wait(pids, attempts) do
    %{rows: [[blocked]]} =
      Repo.query!(
        "SELECT count(*)::int FROM pg_stat_activity WHERE pid = ANY($1::int[]) AND wait_event_type = 'Lock' AND wait_event = 'advisory'",
        [pids]
      )

    if blocked == 2 do
      :ok
    else
      receive do
      after
        10 -> assert_advisory_wait(pids, attempts - 1)
      end
    end
  end
end
