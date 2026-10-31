defmodule Delivest.EventsTest do
  use Delivest.DataCase, async: false
  use Oban.Testing, repo: Delivest.Repo

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Couriers.Delivery
  alias Delivest.Events
  alias Delivest.Events.{DeliverWorker, Event}
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Oms.{Order, Orders}

  defmodule Flaky do
    @behaviour Delivest.Events.Subscriber

    def key, do: :flaky
    def events, do: ["order.status_changed"]

    def handle(event) do
      case Process.get({:flaky, event.id}, 0) do
        0 ->
          Process.put({:flaky, event.id}, 1)
          {:error, :down}

        _seen ->
          send(self(), {:handled, event.id})
          :ok
      end
    end
  end

  defp branch do
    branch = insert(:branch)
    Repo.insert!(%BranchInfo{branch_id: branch.id, couriers: %{}})
    branch
  end

  defp operator(branch) do
    insert(:staff, role: build(:role, permissions: ["orders.update"]), branches: [branch])
    |> Repo.preload([:role, :branches])
  end

  defp events(order, type) do
    Event
    |> where([e], e.aggregate_id == ^order.id and e.type == ^type)
    |> order_by([e], asc: e.id)
    |> Repo.all()
  end

  test "a status change is journaled and handed to every listening subscriber" do
    branch = branch()
    operator = operator(branch)
    order = order_fixture(branch.id)

    {:ok, _order} = Orders.advance_order(order, :accepted, {:staff, operator})

    assert [%Event{} = event] = events(order, "order.status_changed")
    assert event.aggregate_type == "order"
    assert event.branch_id == branch.id
    assert event.actor == %{"kind" => "staff", "id" => operator.id}

    assert %{"from" => "created", "to" => "accepted", "source" => "staff", "v" => 1} =
             event.payload

    for key <- ["couriers", "kitchen", "push"],
        do: assert_enqueued(worker: DeliverWorker, args: %{event_id: event.id, subscriber: key})

    refute_enqueued(worker: DeliverWorker, args: %{event_id: event.id, subscriber: "crm"})
  end

  test "a rolled back transaction leaves neither the event nor the jobs" do
    order = order_fixture(branch().id)
    before = Repo.aggregate(Event, :count)
    Oban.drain_queue(queue: :events, with_safety: false)

    assert {:error, :nope} =
             Repo.transaction(fn ->
               {:ok, _event} = Events.record("order.status_changed", order, %{}, %{kind: :system})
               Repo.rollback(:nope)
             end)

    assert Repo.aggregate(Event, :count) == before
    refute_enqueued(worker: DeliverWorker)
  end

  test "a failed subscriber is retried and a repeated event has no second effect" do
    Application.put_env(:delivest, :event_subscribers, [Flaky, Delivest.Couriers.OrderSubscriber])
    on_exit(fn -> Application.delete_env(:delivest, :event_subscribers) end)

    branch = branch()
    operator = operator(branch)

    order =
      branch.id
      |> order_fixture()
      |> Ecto.Changeset.change(fulfillment_type: :delivery, status: :accepted)
      |> Repo.update!()

    {:ok, _order} = Orders.advance_order(order, :preparing, {:staff, operator})
    [event] = events(order, "order.status_changed")

    assert {:error, :down} =
             perform_job(DeliverWorker, %{event_id: event.id, subscriber: "flaky"})

    assert :ok = perform_job(DeliverWorker, %{event_id: event.id, subscriber: "flaky"})
    assert_received {:handled, id} when id == event.id

    for _run <- 1..2,
        do:
          assert(:ok = perform_job(DeliverWorker, %{event_id: event.id, subscriber: "couriers"}))

    assert [%Delivery{status: :searching}] = Repo.all(where(Delivery, order_id: ^order.id))
  end

  test "an unknown subscriber is given up" do
    assert {:cancel, :unknown_subscriber} =
             perform_job(DeliverWorker, %{event_id: Ecto.UUID.generate(), subscriber: "gone"})
  end

  test "an update carries the changed fields with the old values" do
    order = order_fixture(branch().id)

    {:ok, _order} = Orders.update_payment_method(order, %{"payment_method" => "card_offline"})

    assert [%Event{payload: %{"changes" => changes}}] = events(order, "order.updated")
    assert changes == %{"payment_method" => %{"from" => "cash", "to" => "card_offline"}}
  end

  test "a cancel from the channel names the provider so it is not echoed back" do
    order =
      branch().id
      |> order_fixture()
      |> Order.channel_changeset(%{provider: "yandex_eda", external_id: "ext-1"})
      |> Repo.update!()

    {:ok, _order} = Orders.cancel_order(order, :channel, %{"cancel_reason" => "other"})

    assert [%Event{} = event] = events(order, "order.cancelled")
    assert event.actor == %{"kind" => "channel", "provider" => "yandex_eda"}
    assert Event.from?(event, :channel, :yandex_eda)
    refute Event.from?(event, :crm, :frontpad)
  end

  test "a revert is journaled as a status change back" do
    branch = branch()

    admin =
      insert(:staff,
        role: build(:role, permissions: ["orders.update", "orders.revert"]),
        branches: [branch]
      )
      |> Repo.preload([:role, :branches])

    order = order_fixture(branch.id)
    {:ok, order} = Orders.advance_order(order, :accepted, {:staff, admin})
    {:ok, _order} = Orders.revert_order_status(order, admin, "mistake")

    assert [_accepted, %Event{payload: payload}] = events(order, "order.status_changed")

    assert %{"from" => "accepted", "to" => "created", "reverted" => true, "reason" => "mistake"} =
             payload
  end

  test "a new order is journaled once" do
    order = order_fixture(branch().id)

    assert [%Event{payload: %{"status" => "created", "source" => "app"}}] =
             events(order, "order.created")
  end
end
