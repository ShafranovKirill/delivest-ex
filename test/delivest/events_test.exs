defmodule Delivest.EventsTest do
  use Delivest.DataCase, async: false
  use Oban.Testing, repo: Delivest.Repo

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Couriers.Delivery
  alias Delivest.Audit.Event, as: AuditEvent
  alias Delivest.Events
  alias Delivest.Events.{DeliverWorker, Event, Recovery, Registry}
  alias Delivest.Events.Delivery, as: EventDelivery
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

  defmodule Receiver do
    @behaviour Delivest.Events.Subscriber
    def key, do: :receiver
    def events, do: ["order.status_changed"]

    def handle(event) do
      send(self(), {:receiver_handled, event.id})
      :ok
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
    assert event.sequence > 0
    assert event.actor == %{"kind" => "staff", "id" => operator.id}

    assert %{"from" => "created", "to" => "accepted", "source" => "staff", "v" => 1} =
             event.payload

    for key <- ["couriers", "kitchen", "push"],
        do: assert_enqueued(worker: DeliverWorker, args: %{event_id: event.id, subscriber: key})

    assert_enqueued(
      worker: DeliverWorker,
      queue: :payments,
      args: %{event_id: event.id, subscriber: "payments"}
    )

    expected =
      Registry.listening(event.type)
      |> Enum.map(fn module ->
        key = to_string(module.key())
        {key, to_string(Events.queue(key))}
      end)
      |> Enum.sort()

    jobs =
      Repo.all(
        from j in Oban.Job,
          where: j.worker == "Delivest.Events.DeliverWorker",
          where: fragment("?->>'event_id'", j.args) == ^event.id
      )

    assert jobs |> Enum.map(&{&1.args["subscriber"], &1.queue}) |> Enum.sort() == expected
    assert Repo.aggregate(where(EventDelivery, event_id: ^event.id), :count) == length(expected)

    refute_enqueued(worker: DeliverWorker, args: %{event_id: event.id, subscriber: "crm"})
  end

  test "a rolled back transaction leaves neither the event nor the jobs" do
    order = order_fixture(branch().id)
    before = Repo.aggregate(Event, :count)
    deliveries_before = Repo.aggregate(EventDelivery, :count)
    Oban.drain_queue(queue: :events, with_safety: false)

    assert {:error, :nope} =
             Repo.transaction(fn ->
               {:ok, _event} = Events.record("order.status_changed", order, %{}, %{kind: :system})
               Repo.rollback(:nope)
             end)

    assert Repo.aggregate(Event, :count) == before
    assert Repo.aggregate(EventDelivery, :count) == deliveries_before
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

  test "a failed predecessor blocks its subscriber, while another subscriber proceeds" do
    Application.put_env(:delivest, :event_subscribers, [Flaky, Receiver])
    on_exit(fn -> Application.delete_env(:delivest, :event_subscribers) end)
    order = order_fixture(branch().id)
    {:ok, first} = Events.record("order.status_changed", order, %{}, %{kind: :system})
    {:ok, second} = Events.record("order.status_changed", order, %{}, %{kind: :system})
    second_id = second.id
    assert second.sequence == first.sequence + 1

    assert {:error, :down} =
             perform_job(DeliverWorker, %{event_id: first.id, subscriber: "flaky"})

    assert {:snooze, 5} = perform_job(DeliverWorker, %{event_id: second.id, subscriber: "flaky"})
    refute_received {:handled, ^second_id}

    assert :ok = perform_job(DeliverWorker, %{event_id: first.id, subscriber: "receiver"})
    assert :ok = perform_job(DeliverWorker, %{event_id: second.id, subscriber: "receiver"})
    assert_received {:receiver_handled, ^second_id}
    assert :ok = perform_job(DeliverWorker, %{event_id: first.id, subscriber: "flaky"})

    assert {:error, :down} =
             perform_job(DeliverWorker, %{event_id: second.id, subscriber: "flaky"})

    assert :ok = perform_job(DeliverWorker, %{event_id: second.id, subscriber: "flaky"})
    assert :ok = perform_job(DeliverWorker, %{event_id: second.id, subscriber: "flaky"})
    assert_received {:handled, ^second_id}
    refute_received {:handled, ^second_id}
  end

  test "a legacy job with missing ledger enters the same delivery path" do
    Application.put_env(:delivest, :event_subscribers, [Receiver])
    on_exit(fn -> Application.delete_env(:delivest, :event_subscribers) end)
    order = order_fixture(branch().id)
    {:ok, event} = Events.record("order.status_changed", order, %{}, %{kind: :system})
    Repo.delete_all(where(EventDelivery, event_id: ^event.id))

    assert :ok = perform_job(DeliverWorker, %{event_id: event.id, subscriber: "receiver"})

    assert %EventDelivery{status: "delivered"} =
             Repo.get_by(EventDelivery, event_id: event.id, subscriber: "receiver")

    assert_received {:receiver_handled, id} when id == event.id
  end

  test "recovery requires admin, reason, and a stopped job; resolve permits successors" do
    Application.put_env(:delivest, :event_subscribers, [Receiver])
    on_exit(fn -> Application.delete_env(:delivest, :event_subscribers) end)
    order = order_fixture(branch().id)
    {:ok, event} = Events.record("order.status_changed", order, %{}, %{kind: :system})
    {:ok, successor} = Events.record("order.status_changed", order, %{}, %{kind: :system})
    nonadmin = insert(:staff, role: build(:role, permissions: []))
    admin = insert(:staff, role: build(:role, permissions: ["admin"]))

    assert {:error, :invalid_arguments} = Recovery.resolve(event.id, "receiver", admin.id, " ")
    assert {:error, :forbidden} = Recovery.resolve(event.id, "receiver", nonadmin.id, "skip")
    assert {:error, :active_job} = Recovery.resolve(event.id, "receiver", admin.id, "skip")

    assert {:snooze, 5} =
             perform_job(DeliverWorker, %{event_id: successor.id, subscriber: "receiver"})

    Repo.update_all(
      from(j in Oban.Job,
        where: j.worker == "Delivest.Events.DeliverWorker",
        where: fragment("?->>'event_id'", j.args) == ^event.id
      ),
      set: [state: "discarded"]
    )

    assert {:ok, :ok} = Recovery.resolve(event.id, "receiver", admin.id, "safe to skip")

    assert %EventDelivery{status: "resolved"} =
             Repo.get_by(EventDelivery, event_id: event.id, subscriber: "receiver")

    assert :ok =
             perform_job(DeliverWorker, %{event_id: successor.id, subscriber: "receiver"})

    assert_received {:receiver_handled, id} when id == successor.id

    assert %AuditEvent{actor_id: actor_id, metadata: %{"reason" => "safe to skip"}} =
             Repo.get_by!(AuditEvent, action: "events.resolve", subject_id: event.id)

    assert actor_id == admin.id

    assert :ok = perform_job(DeliverWorker, %{event_id: event.id, subscriber: "receiver"})
    refute_received {:receiver_handled, _}
    assert {:error, :already_closed} = Recovery.retry(event.id, "receiver", admin.id, "retry")
  end

  test "an administrator can retry a pending delivery after its job is pruned" do
    Application.put_env(:delivest, :event_subscribers, [Receiver])
    on_exit(fn -> Application.delete_env(:delivest, :event_subscribers) end)
    order = order_fixture(branch().id)
    {:ok, event} = Events.record("order.status_changed", order, %{}, %{kind: :system})
    admin = insert(:staff, role: build(:role, permissions: ["admin"]))

    Repo.delete_all(
      from j in Oban.Job,
        where: j.worker == "Delivest.Events.DeliverWorker",
        where: fragment("?->>'event_id'", j.args) == ^event.id
    )

    assert {:ok, :ok} = Recovery.retry(event.id, "receiver", admin.id, "pruned job")

    assert %AuditEvent{actor_id: actor_id, metadata: %{"reason" => "pruned job"}} =
             Repo.get_by!(AuditEvent, action: "events.retry", subject_id: event.id)

    assert actor_id == admin.id
    assert_enqueued(worker: DeliverWorker, args: %{event_id: event.id, subscriber: "receiver"})

    assert [%{event_id: id, subscriber: "receiver"}] =
             Enum.filter(Recovery.list(), &(&1.event_id == event.id))

    assert id == event.id

    assert :ok = perform_job(DeliverWorker, %{event_id: event.id, subscriber: "receiver"})

    assert %EventDelivery{status: "delivered"} =
             Repo.get_by(EventDelivery, event_id: event.id, subscriber: "receiver")

    assert {:error, :already_closed} = Recovery.resolve(event.id, "receiver", admin.id, "late")
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
