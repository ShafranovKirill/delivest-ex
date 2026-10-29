defmodule Delivest.Push.CourierPushTest do
  use Delivest.DataCase, async: true
  use Oban.Testing, repo: Delivest.Repo

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.{Couriers, Oms, Push, PushClient}
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Oms.Orders
  alias Delivest.Push.Worker
  alias DelivestWeb.Client.Order.OrderJSON

  setup do
    branch = insert(:branch)
    Repo.insert!(%BranchInfo{branch_id: branch.id, couriers: %{}})

    operator =
      insert(:staff, role: build(:role, permissions: ["orders.update"]), branches: [branch])
      |> Repo.preload([:role, :branches])

    courier =
      insert(:staff,
        name: "Иван",
        phone: "+79001112233",
        role: build(:role, permissions: ["orders.deliver"]),
        branches: [branch]
      )
      |> Repo.preload([:role, :branches])

    order =
      branch.id
      |> order_fixture()
      |> Ecto.Changeset.change(fulfillment_type: :delivery, session_id: "courier-push")
      |> Repo.update!()

    client = PushClient.new()
    {:ok, _subscription} = Push.subscribe(order, PushClient.subscription_attrs(client))

    test_pid = self()

    Req.Test.stub(Delivest.Push.Sender, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:push, body})
      Plug.Conn.send_resp(conn, 201, "")
    end)

    %{branch: branch, operator: operator, courier: courier, order: order, client: client}
  end

  defp advance(order, statuses, operator) do
    Enum.reduce(statuses, order, fn to, order ->
      {:ok, order} = Orders.advance_order(order, to, {:staff, operator})
      order
    end)
  end

  defp pushed(ctx) do
    :ok = perform_job(Worker, %{"order_id" => ctx.order.id})
    collect(ctx.client, [])
  end

  defp collect(client, bodies) do
    receive do
      {:push, body} -> collect(client, [PushClient.decrypt(client, body)["body"] | bodies])
    after
      0 -> Enum.reverse(bodies)
    end
  end

  test "the customer learns who is coming and who brings the order", ctx do
    order = advance(ctx.order, [:accepted, :preparing], ctx.operator)
    pushed(ctx)

    Orders.subscribe_owner(:session, order.session_id)
    delivery = Couriers.active(order.id)
    {:ok, _delivery} = Couriers.take(ctx.courier, ctx.branch.id, delivery.id)

    assert_receive {:client_order, published}

    assert %{courier: %{name: "Иван", phone: "+79001112233", tracking_url: nil}} =
             OrderJSON.active_order_data(published)

    assert pushed(ctx) == ["Courier Иван is heading to pick up order #{order.number}"]
    assert pushed(ctx) == []

    order = advance(Repo.reload!(order), [:ready], ctx.operator)
    pushed(ctx)

    {:ok, _order} = Couriers.pick_up(ctx.courier, ctx.branch.id, delivery.id)
    assert pushed(ctx) == ["Courier Иван is on the way with order #{order.number}"]
  end

  test "no courier is shown before one takes the order", ctx do
    order = advance(ctx.order, [:accepted, :preparing], ctx.operator)
    [order] = Oms.Orders.list_active_orders(order.session_id)

    assert %{courier: nil} = OrderJSON.active_order_data(order)
    assert pushed(ctx) == ["Order #{order.number} is being prepared"]
  end
end
