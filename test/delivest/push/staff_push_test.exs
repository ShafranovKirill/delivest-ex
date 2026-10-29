defmodule Delivest.Push.StaffPushTest do
  use Delivest.DataCase, async: true
  use Oban.Testing, repo: Delivest.Repo

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.{Couriers, Push, PushClient}
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Oms.{Kitchen, Orders}
  alias Delivest.Push.{StaffSubscription, StaffWorker}

  setup do
    branch = insert(:branch)
    Repo.insert!(%BranchInfo{branch_id: branch.id, couriers: %{}})
    test_pid = self()

    Req.Test.stub(Delivest.Push.Sender, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:push, conn.request_path, body})
      Plug.Conn.send_resp(conn, 201, "")
    end)

    %{
      branch: branch,
      operator: device(["orders.update"], branch),
      courier: device(["orders.deliver"], branch),
      other: device(["orders.update"], insert(:branch))
    }
  end

  defp device(permissions, branch) do
    staff =
      insert(:staff, role: build(:role, permissions: permissions), branches: [branch])
      |> Repo.preload([:role, :branches])

    client = PushClient.new()
    {:ok, subscription} = Push.subscribe_staff(staff, PushClient.subscription_attrs(client))
    %{staff: staff, client: client, path: URI.parse(subscription.endpoint).path}
  end

  defp delivery_order(branch) do
    branch.id
    |> order_fixture()
    |> Ecto.Changeset.change(fulfillment_type: :delivery)
    |> Repo.update!()
  end

  defp received(device) do
    receive do
      {:push, path, body} when path == device.path ->
        PushClient.decrypt(device.client, body)["body"]
    after
      0 -> nil
    end
  end

  defp run_jobs do
    for job <- all_enqueued(worker: StaffWorker), do: perform_job(StaffWorker, job.args)
  end

  test "operators of the branch hear about a new order", ctx do
    order = order_fixture(ctx.branch.id)
    run_jobs()

    assert received(ctx.operator) == "New order ##{order.daily_number}"
    refute received(ctx.courier)
    refute received(ctx.other)
  end

  test "an order accepted before the push goes out is not announced", ctx do
    order = order_fixture(ctx.branch.id)
    {:ok, _order} = Orders.advance_order(order, :accepted, {:staff, ctx.operator.staff})
    run_jobs()

    refute received(ctx.operator)
  end

  test "couriers hear about a new request and the one given an order", ctx do
    order = delivery_order(ctx.branch)
    {:ok, order} = Orders.advance_order(order, :accepted, {:staff, ctx.operator.staff})
    {:ok, _delivery} = Couriers.find(ctx.operator.staff, order)
    run_jobs()

    assert received(ctx.courier) == "New delivery request ##{order.daily_number}"
    refute received(ctx.operator)

    {:ok, _delivery} = Couriers.assign(ctx.operator.staff, order, ctx.courier.staff.id)
    run_jobs()

    assert received(ctx.courier) == "You were given order ##{order.daily_number}"
  end

  test "operators hear the kitchen finished an order", ctx do
    kitchen =
      insert(:staff, role: build(:role, permissions: ["orders.cook"]), branches: [ctx.branch])

    kitchen = Repo.preload(kitchen, [:role, :branches])
    order = order_fixture(ctx.branch.id)
    {:ok, order} = Orders.advance_order(order, :accepted, {:staff, ctx.operator.staff})
    {:ok, order} = Orders.advance_order(order, :preparing, {:staff, kitchen})

    {:ok, _order} = Kitchen.finish_ready(order.id, kitchen.id)
    run_jobs()

    assert received(ctx.operator) == "Order ##{order.daily_number} is ready"
  end

  test "operators hear the channel cancelled an order", ctx do
    order = order_fixture(ctx.branch.id)
    {:ok, _order} = Orders.cancel_order(order, :channel, %{"cancel_reason" => "other"})
    run_jobs()

    assert received(ctx.operator) == "Order ##{order.daily_number} was cancelled by the channel"
  end

  test "a gone device is dropped", ctx do
    Req.Test.stub(Delivest.Push.Sender, &Plug.Conn.send_resp(&1, 410, ""))
    order_fixture(ctx.branch.id)
    run_jobs()

    refute Repo.get_by(StaffSubscription, staff_id: ctx.operator.staff.id)
  end
end
