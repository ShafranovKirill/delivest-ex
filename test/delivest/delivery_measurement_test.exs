defmodule Delivest.DeliveryMeasurementTest do
  use Delivest.DataCase, async: false

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.{Couriers, DeliveryMeasurement, Features, Repo}
  alias Delivest.Couriers.Delivery
  alias Delivest.DeliveryMeasurement.ActualEvent
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Oms.Orders

  setup do
    branch = insert(:branch)
    foreign = insert(:branch)
    Repo.insert!(%BranchInfo{branch_id: branch.id})
    {:ok, _} = Features.configure("couriers", :franchise, true, actor: "test")
    {:ok, _} = Features.configure("couriers", {:branch, branch.id}, true, actor: "test")

    staff =
      insert(:staff,
        role: build(:role, permissions: ["orders.update"]),
        branches: [branch]
      )
      |> Repo.preload([:role, :branches])

    courier =
      insert(:staff,
        role: build(:role, permissions: ["orders.deliver"]),
        branches: [branch]
      )
      |> Repo.preload([:role, :branches])

    order =
      branch.id
      |> order_fixture()
      |> Ecto.Changeset.change(fulfillment_type: :delivery)
      |> Repo.update!()

    {:ok, order} = Orders.advance_order(order, :accepted, {:staff, staff})
    deliver_events()
    %{branch: branch, foreign: foreign, staff: staff, courier: courier, order: order}
  end

  test "first promise remains baseline; changes require a reason and foreign branch is forbidden",
       ctx do
    first = DateTime.add(DateTime.utc_now(), 7200, :second) |> DateTime.truncate(:second)
    later = DateTime.add(first, 1800, :second)

    assert {:error, :forbidden} =
             DeliveryMeasurement.confirm_promise(ctx.staff, ctx.foreign.id, ctx.order.id, first)

    assert {:ok, order} =
             DeliveryMeasurement.confirm_promise(ctx.staff, ctx.branch.id, ctx.order.id, first)

    assert order.initial_promised_delivery_at == first

    assert {:ok, _} =
             DeliveryMeasurement.confirm_promise(ctx.staff, ctx.branch.id, ctx.order.id, first)

    assert {:error, :reason_required} =
             DeliveryMeasurement.confirm_promise(ctx.staff, ctx.branch.id, ctx.order.id, later)

    assert {:ok, changed} =
             DeliveryMeasurement.confirm_promise(
               ctx.staff,
               ctx.branch.id,
               ctx.order.id,
               later,
               "Позвонили покупателю"
             )

    assert changed.initial_promised_delivery_at == first
    assert changed.promised_delivery_at == later

    assert DeliveryMeasurement.history(ctx.order.id)
           |> Enum.map(& &1.promised_at)
           |> Enum.sort(DateTime) == [first, later]
  end

  test "handover confirms actual exactly once; generic completion cannot confirm", ctx do
    {:ok, preparing} = Orders.advance_order(ctx.order, :preparing, {:staff, ctx.staff})
    deliver_events()
    delivery = Couriers.active(ctx.order.id)
    assert {:ok, _} = Couriers.take(ctx.courier, ctx.branch.id, delivery.id)
    {:ok, ready} = Orders.advance_order(preparing, :ready, {:staff, ctx.staff})
    assert {:ok, _} = Couriers.pick_up(ctx.courier, ctx.branch.id, delivery.id)

    outsider =
      insert(:staff, role: build(:role, permissions: ["orders.deliver"]), branches: [ctx.foreign])
      |> Repo.preload([:role, :branches])

    assert {:error, :forbidden} = Couriers.hand_over(outsider, ctx.branch.id, delivery.id)
    assert is_nil(Repo.reload!(ready).delivered_at)
    assert {:ok, _} = Couriers.hand_over(ctx.courier, ctx.branch.id, delivery.id)
    actual = Repo.reload!(ready).delivered_at
    assert %DateTime{} = actual
    assert Repo.reload!(ready).delivery_actual_source == "staff_handover"

    assert %ActualEvent{
             source: "staff_handover",
             event_id: "staff_handover:" <> _,
             occurred_at: ^actual,
             received_at: ^actual
           } = Repo.get_by!(ActualEvent, order_id: ready.id, source: "staff_handover")

    assert {:error, _} = Couriers.hand_over(ctx.courier, ctx.branch.id, delivery.id)
    assert Repo.reload!(ready).delivered_at == actual
    assert Repo.aggregate(ActualEvent, :count, :id) == 1
  end

  test "generic staff completion and provider status sync are not handover evidence", ctx do
    completed =
      Enum.reduce([:preparing, :ready, :delivering, :completed], ctx.order, fn status, order ->
        {:ok, next} = Orders.advance_order(order, status, {:staff, ctx.staff})
        next
      end)

    assert completed.status == :completed
    assert is_nil(Repo.reload!(completed).delivered_at)

    assert {:error, :not_eligible} =
             DeliveryMeasurement.record_provider_actual(
               completed.id,
               :yandex_delivery,
               "provider-sync-1",
               DateTime.utc_now()
             )

    assert is_nil(Repo.reload!(completed).delivered_at)
    assert Repo.aggregate(ActualEvent, :count, :id) == 0
  end

  test "invalid and missing provider order IDs return errors, not exceptions" do
    assert {:error, :not_found} =
             DeliveryMeasurement.record_provider_actual(
               "invalid",
               :yandex_delivery,
               "evt",
               DateTime.utc_now()
             )

    assert {:error, :not_found} =
             DeliveryMeasurement.record_provider_actual(
               Ecto.UUID.generate(),
               :yandex_delivery,
               "evt",
               DateTime.utc_now()
             )
  end

  test "provider events are deduplicated without overwriting first actual", ctx do
    order = Repo.update!(Ecto.Changeset.change(ctx.order, status: :completed))

    Repo.insert!(%Delivery{
      order_id: order.id,
      branch_id: ctx.branch.id,
      provider: :yandex,
      status: :delivered,
      external_id: "provider-delivery-1"
    })

    occurred = DateTime.add(order.inserted_at, 1, :second) |> DateTime.truncate(:second)
    later = DateTime.add(occurred, 1, :second)

    assert {:ok, _} =
             DeliveryMeasurement.record_provider_actual(
               order.id,
               :yandex_delivery,
               "evt-1",
               occurred
             )

    assert {:ok, _} =
             DeliveryMeasurement.record_provider_actual(
               order.id,
               :yandex_delivery,
               "evt-1",
               occurred
             )

    assert {:error, :event_conflict} =
             DeliveryMeasurement.record_provider_actual(
               order.id,
               :yandex_delivery,
               "evt-1",
               later
             )

    assert {:ok, _} =
             DeliveryMeasurement.record_provider_actual(
               order.id,
               :yandex_delivery,
               "evt-2",
               later
             )

    assert Repo.reload!(order).delivered_at == occurred
  end
end
