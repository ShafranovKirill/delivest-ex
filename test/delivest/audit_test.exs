defmodule Delivest.AuditTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Audit
  alias Delivest.Audit.Event

  test "track records a successful action with actor and subject snapshots" do
    staff = insert(:staff, name: "Ivan")
    product = insert(:product, name: "Pizza")
    Audit.subscribe()

    assert {:ok, ^product} = Audit.track({:ok, product}, staff, "product.updated")

    assert [%Event{} = event] = Repo.all(Event)
    assert event.action == "product.updated"
    assert event.actor_type == :staff
    assert event.actor_name == "Ivan"
    assert event.subject_type == "product"
    assert event.subject_label == "Pizza"
    assert_receive {:audit_event, %Event{id: id}}
    assert id == event.id
  end

  test "track keeps the branch and metadata" do
    branch_id = Ecto.UUID.generate()
    product = insert(:product)

    Audit.track({:ok, product}, :system, "product.imported",
      branch_id: branch_id,
      metadata: %{count: 3}
    )

    assert [%Event{actor_type: :system, branch_id: ^branch_id, metadata: %{"count" => 3}}] =
             Repo.all(Event) |> Enum.map(&Repo.reload!/1)
  end

  test "track passes errors through without recording" do
    assert {:error, :forbidden} = Audit.track({:error, :forbidden}, nil, "product.updated")
    assert Repo.all(Event) == []
  end

  test "events are listed newest first" do
    product = insert(:product)
    Audit.record(:system, "product.created", product)
    Audit.record(:system, "product.updated", product)

    assert {:ok, {[latest, _first], _meta}} = Audit.list_events(%{})
    assert latest.action == "product.updated"
  end
end
