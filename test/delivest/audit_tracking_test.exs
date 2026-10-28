defmodule Delivest.AuditTrackingTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Audit.Event
  alias Delivest.{Net, Oms}

  @branch_id "00000000-0000-4000-8000-000000000002"

  defp events, do: Repo.all(from(e in Event, order_by: e.inserted_at))

  defp admin, do: insert(:staff, name: "Admin", role: insert(:role, permissions: ["admin"]))

  test "product creation is recorded with the staff and branch" do
    staff = admin()

    {:ok, product} = Net.create_product(staff, @branch_id, %{"name" => "Soup", "price" => 100})

    assert [%Event{action: "product.created", actor_name: "Admin", branch_id: @branch_id} = e] =
             events()

    assert e.subject_id == product.id
  end

  test "forbidden actions are not recorded" do
    staff = insert(:staff, role: insert(:role, permissions: []))

    assert {:error, :forbidden} = Net.create_product(staff, @branch_id, %{"name" => "Soup"})
    assert events() == []
  end

  test "guest order is recorded as created by the customer" do
    order_fixture(@branch_id, attrs: %{"customer_phone" => "+79990001122"})

    assert [%Event{action: "client.created"}, %Event{action: "order.created"} = created] =
             events()

    assert created.actor_type == :client
    assert created.branch_id == @branch_id
  end

  test "status change records the step and who made it" do
    order = order_fixture(@branch_id)
    staff = admin()

    {:ok, _} = Oms.advance_order(order, :accepted, {:staff, staff})

    assert %Event{action: "order.status_changed", actor_type: :staff, metadata: metadata} =
             List.last(events())

    assert metadata == %{"from" => "created", "to" => "accepted", "source" => "staff"}
  end

  test "payment change keeps the changed fields" do
    order = order_fixture(@branch_id)
    staff = admin()

    {:ok, _} = Oms.update_payment_method(order, %{"payment_method" => "card_offline"}, staff)

    assert %Event{action: "order.details_changed", actor_type: :staff, metadata: metadata} =
             List.last(events())

    assert metadata == %{"payment_method" => "card_offline"}
  end
end
