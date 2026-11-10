defmodule Delivest.SegmentsTest do
  use Delivest.DataCase, async: false
  import Delivest.Factory

  alias Delivest.{Features, Repo, Segments}
  alias Delivest.Segments.Rules
  alias Delivest.Segments.Refresh
  alias Delivest.Background.Schedule
  alias Delivest.OrderFixtures
  alias Delivest.Oms.Order
  alias Delivest.Payments.{Payment, Refund}

  @rules %{
    "version" => 1,
    "match" => "all",
    "conditions" => [
      %{"metric" => "order_count", "op" => "gte", "value" => 1}
    ]
  }

  test "rule format is bounded and a customer without an order has no last-order age" do
    assert {:ok, _} = Rules.validate(@rules)

    assert {:error, :invalid_rules} =
             Rules.validate(%{
               @rules
               | "conditions" => List.duplicate(hd(@rules["conditions"]), 9)
             })

    assert {:error, :invalid_rules} =
             Rules.validate(%{
               @rules
               | "conditions" => [%{"metric" => "sql", "op" => "eq", "value" => 1}]
             })

    zero = %{order_count: 0, total_spent: 0, last_order_at: nil}

    refute Rules.match?(
             %{
               @rules
               | "conditions" => [
                   %{"metric" => "days_since_last_order", "op" => "gte", "value" => 0}
                 ]
             },
             zero
           )

    assert Rules.match?(
             %{
               @rules
               | "conditions" => [%{"metric" => "order_count", "op" => "eq", "value" => 0}]
             },
             zero
           )
  end

  test "feature gate, branch scope, network permission and manual membership" do
    branch_a = insert(:branch, is_active: true)
    branch_b = insert(:branch, is_active: true)
    role = insert(:role, permissions: ["segments.read", "segments.manage"])
    staff = insert(:staff, role: role)
    Repo.insert!(%Delivest.Identity.StaffBranch{staff_id: staff.id, branch_id: branch_a.id})
    client_a = insert(:client)

    assert {:error, :disabled} = Segments.list(staff)
    {:ok, _} = Features.configure("segments", :franchise, true, actor: "test")
    {:ok, _} = Features.configure("segments", {:branch, branch_a.id}, true, actor: "test")
    {:ok, _} = Features.configure("segments", {:branch, branch_b.id}, true, actor: "test")

    assert {:error, :forbidden} =
             Segments.create(staff, %{name: "Network", kind: :manual, scope: :franchise})

    assert {:error, :forbidden} =
             Segments.create(staff, %{name: "Other", kind: :manual, scope: :branches}, [
               branch_b.id
             ])

    assert {:ok, segment} =
             Segments.create(staff, %{name: "Local", kind: :manual, scope: :branches}, [
               branch_a.id
             ])

    assert {:ok, [listed]} = Segments.list(staff)
    assert listed.id == segment.id
    assert {:error, :forbidden} = Segments.add_member(staff, segment.id, client_a.id)
    assert {:error, :not_found} = Segments.get(staff, "not-a-uuid")
  end

  test "refresh counts completed orders, subtracts succeeded refunds and keeps branch isolation" do
    branch_a = insert(:branch, is_active: true)
    branch_b = insert(:branch, is_active: true)
    client = insert(:client)

    manager =
      insert(:staff, role: insert(:role, permissions: ["segments.read", "segments.manage"]))

    Repo.insert!(%Delivest.Identity.StaffBranch{staff_id: manager.id, branch_id: branch_a.id})
    {:ok, _} = Features.configure("segments", :franchise, true, actor: "test")
    {:ok, _} = Features.configure("segments", {:branch, branch_a.id}, true, actor: "test")
    {:ok, _} = Features.configure("segments", {:branch, branch_b.id}, true, actor: "test")

    completed = OrderFixtures.order_fixture(branch_a.id)

    Repo.update_all(from(o in Order, where: o.id == ^completed.id),
      set: [status: :completed, client_id: client.id]
    )

    cancelled = OrderFixtures.order_fixture(branch_a.id)

    Repo.update_all(from(o in Order, where: o.id == ^cancelled.id),
      set: [status: :cancelled, client_id: client.id]
    )

    other = OrderFixtures.order_fixture(branch_b.id)

    Repo.update_all(from(o in Order, where: o.id == ^other.id),
      set: [status: :completed, client_id: client.id]
    )

    payment =
      Repo.insert!(%Payment{
        order_id: completed.id,
        branch_id: branch_a.id,
        method: :cash,
        amount: 15_000,
        status: :paid
      })

    refund =
      Repo.insert!(%Refund{
        order_id: completed.id,
        payment_id: payment.id,
        amount: 5_000,
        status: :succeeded
      })

    rules = %{
      "version" => 1,
      "match" => "all",
      "conditions" => [
        %{"metric" => "order_count", "op" => "eq", "value" => 1},
        %{"metric" => "total_spent", "op" => "eq", "value" => 10_000}
      ]
    }

    assert {:ok, group} =
             Segments.create(
               manager,
               %{name: "Refund aware", kind: :dynamic, scope: :branches, rules: rules},
               [branch_a.id]
             )

    context = refresh_context()
    assert :ok = Refresh.perform(:franchise, context)
    assert {:ok, [member]} = Segments.list_members(manager, group.id)
    assert member.id == client.id
    Repo.update_all(from(r in Refund, where: r.id == ^refund.id), set: [status: :failed])
    assert dirty_count(branch_a.id) == 1
    assert :ok = Refresh.perform(:franchise, refresh_context())
    assert {:ok, []} = Segments.list_members(manager, group.id)
  end

  test "local zero-order rule never exposes clients known only in another branch" do
    branch_a = insert(:branch, is_active: true)
    branch_b = insert(:branch, is_active: true)
    local = insert(:client)
    foreign = insert(:client)

    manager =
      insert(:staff, role: insert(:role, permissions: ["segments.read", "segments.manage"]))

    Repo.insert!(%Delivest.Identity.StaffBranch{staff_id: manager.id, branch_id: branch_a.id})
    {:ok, _} = Features.configure("segments", :franchise, true, actor: "test")
    {:ok, _} = Features.configure("segments", {:branch, branch_a.id}, true, actor: "test")
    {:ok, _} = Features.configure("segments", {:branch, branch_b.id}, true, actor: "test")
    a_order = OrderFixtures.order_fixture(branch_a.id)
    Repo.update_all(from(o in Order, where: o.id == ^a_order.id), set: [client_id: local.id])
    b_order = OrderFixtures.order_fixture(branch_b.id)
    Repo.update_all(from(o in Order, where: o.id == ^b_order.id), set: [client_id: foreign.id])

    rules = %{
      "version" => 1,
      "match" => "all",
      "conditions" => [
        %{"metric" => "order_count", "op" => "eq", "value" => 0}
      ]
    }

    assert {:ok, group} =
             Segments.create(
               manager,
               %{name: "No completed", kind: :dynamic, scope: :branches, rules: rules},
               [branch_a.id]
             )

    assert :ok = Refresh.perform(:franchise, refresh_context())
    assert {:ok, [only]} = Segments.list_members(manager, group.id)
    assert only.id == local.id
  end

  test "dirty queue is gated, skips unrelated order edits, and acknowledges a successful refresh" do
    branch = insert(:branch, is_active: true)
    client = insert(:client)
    order = OrderFixtures.order_fixture(branch.id)

    Repo.update_all(from(o in Order, where: o.id == ^order.id),
      set: [client_id: client.id, status: :completed]
    )

    assert dirty_count(branch.id) == 0
    {:ok, _} = Features.configure("segments", :franchise, true, actor: "test")
    {:ok, _} = Features.configure("segments", {:branch, branch.id}, true, actor: "test")

    manager =
      insert(:staff, role: insert(:role, permissions: ["segments.read", "segments.manage"]))

    Repo.insert!(%Delivest.Identity.StaffBranch{staff_id: manager.id, branch_id: branch.id})

    assert {:ok, group} =
             Segments.create(
               manager,
               %{name: "Purchased", kind: :dynamic, scope: :branches, rules: @rules},
               [branch.id]
             )

    Repo.update_all(from(o in Order, where: o.id == ^order.id), set: [comment: "ignored"])
    assert dirty_count(branch.id) == 0
    Repo.update_all(from(o in Order, where: o.id == ^order.id), set: [total_amount: 16_000])
    assert dirty_count(branch.id) == 1
    old_revision = dirty_revision(branch.id, client.id)
    assert :ok = Refresh.perform(:franchise, refresh_context())
    assert dirty_count(branch.id) == 0
    assert {:ok, [_]} = Segments.list_members(manager, group.id)
    Repo.update_all(from(o in Order, where: o.id == ^order.id), set: [total_amount: 17_000])
    assert dirty_revision(branch.id, client.id) > old_revision
    assert :ok = Refresh.perform(:franchise, refresh_context())
    assert dirty_count(branch.id) == 0
  end

  test "parent reenable rebases metrics after off-period changes and stale edits cannot overwrite" do
    branch = insert(:branch, is_active: true)
    client = insert(:client)

    manager =
      insert(:staff, role: insert(:role, permissions: ["segments.read", "segments.manage"]))

    Repo.insert!(%Delivest.Identity.StaffBranch{staff_id: manager.id, branch_id: branch.id})
    {:ok, _} = Features.configure("segments", :franchise, true, actor: "test")
    {:ok, _} = Features.configure("segments", {:branch, branch.id}, true, actor: "test")
    order = OrderFixtures.order_fixture(branch.id)

    Repo.update_all(from(o in Order, where: o.id == ^order.id),
      set: [client_id: client.id, status: :completed]
    )

    assert {:ok, group} =
             Segments.create(
               manager,
               %{
                 name: "One purchase",
                 kind: :dynamic,
                 scope: :branches,
                 rules: %{
                   "version" => 1,
                   "match" => "all",
                   "conditions" => [
                     %{"metric" => "order_count", "op" => "eq", "value" => 1}
                   ]
                 }
               },
               [branch.id]
             )

    assert :ok = Refresh.perform(:franchise, refresh_context())
    published = Repo.reload!(group).published_snapshot_id
    assert published
    assert {:ok, [_]} = Segments.list_members(manager, group.id)

    assert {:ok, updated} =
             Segments.update(manager, group.id, %{"name" => "Renamed", "expected_revision" => 1})

    assert {:error, :stale} =
             Segments.update(manager, group.id, %{"name" => "Wrong", "expected_revision" => 1})

    assert Repo.reload!(updated).published_snapshot_id == published
    {:ok, _} = Features.configure("segments", :franchise, false, actor: "test")
    Repo.update_all(from(o in Order, where: o.id == ^order.id), set: [status: :cancelled])
    assert dirty_count(branch.id) == 0
    {:ok, _} = Features.configure("segments", :franchise, true, actor: "test")
    assert :ok = Refresh.perform(:franchise, refresh_context())
    assert {:ok, []} = Segments.list_members(manager, group.id)
  end

  test "manual creation with an ineligible client leaves no partial group" do
    branch = insert(:branch, is_active: true)
    valid = insert(:client)
    invalid = insert(:client)

    manager =
      insert(:staff, role: insert(:role, permissions: ["segments.read", "segments.manage"]))

    Repo.insert!(%Delivest.Identity.StaffBranch{staff_id: manager.id, branch_id: branch.id})
    {:ok, _} = Features.configure("segments", :franchise, true, actor: "test")
    {:ok, _} = Features.configure("segments", {:branch, branch.id}, true, actor: "test")
    order = OrderFixtures.order_fixture(branch.id)
    Repo.update_all(from(o in Order, where: o.id == ^order.id), set: [client_id: valid.id])

    assert {:error, :invalid_members} =
             Segments.create(
               manager,
               %{name: "Reject incomplete", kind: :manual, scope: :branches},
               [branch.id],
               [valid.id, invalid.id]
             )

    refute Repo.exists?(from s in Delivest.Segments.Segment, where: s.name == "Reject incomplete")
  end

  test "revoked generation cannot republish an old snapshot" do
    branch = insert(:branch, is_active: true)
    client = insert(:client)

    manager =
      insert(:staff, role: insert(:role, permissions: ["segments.read", "segments.manage"]))

    Repo.insert!(%Delivest.Identity.StaffBranch{staff_id: manager.id, branch_id: branch.id})
    {:ok, _} = Features.configure("segments", :franchise, true, actor: "test")
    {:ok, _} = Features.configure("segments", {:branch, branch.id}, true, actor: "test")
    order = OrderFixtures.order_fixture(branch.id)

    Repo.update_all(from(o in Order, where: o.id == ^order.id),
      set: [client_id: client.id, status: :completed]
    )

    {:ok, group} =
      Segments.create(
        manager,
        %{name: "Stable", kind: :dynamic, scope: :branches, rules: @rules},
        [branch.id]
      )

    context = refresh_context()
    assert :ok = Refresh.perform(:franchise, context)
    snapshot = Repo.reload!(group).published_snapshot_id
    {:ok, _} = Features.configure("segments", {:branch, branch.id}, false, actor: "test")
    {:ok, _} = Features.configure("segments", {:branch, branch.id}, true, actor: "test")
    assert {:error, :disabled} = Refresh.perform(:franchise, context)
    assert Repo.reload!(group).published_snapshot_id == snapshot
  end

  test "temporarily inactive but enabled branch retains historical segment metrics" do
    branch = insert(:branch, is_active: false)
    client = insert(:client)

    manager =
      insert(:staff, role: insert(:role, permissions: ["segments.read", "segments.manage"]))

    Repo.insert!(%Delivest.Identity.StaffBranch{staff_id: manager.id, branch_id: branch.id})
    {:ok, _} = Features.configure("segments", :franchise, true, actor: "test")
    {:ok, _} = Features.configure("segments", {:branch, branch.id}, true, actor: "test")
    assert Segments.available?(manager)
    order = OrderFixtures.order_fixture(branch.id)

    Repo.update_all(from(o in Order, where: o.id == ^order.id),
      set: [client_id: client.id, status: :completed]
    )

    {:ok, group} =
      Segments.create(
        manager,
        %{name: "Closed branch history", kind: :dynamic, scope: :branches, rules: @rules},
        [branch.id]
      )

    assert :ok = Refresh.perform(:franchise, refresh_context())
    assert {:ok, [member]} = Segments.list_members(manager, group.id)
    assert member.id == client.id
  end

  defp dirty_count(branch_id) do
    Repo.query!("SELECT count(*) FROM segment_dirty_clients WHERE branch_id=$1", [
      Ecto.UUID.dump!(branch_id)
    ]).rows
    |> hd()
    |> hd()
  end

  defp dirty_revision(branch_id, client_id) do
    Repo.query!(
      "SELECT revision FROM segment_dirty_clients WHERE branch_id=$1 AND client_id=$2",
      [Ecto.UUID.dump!(branch_id), Ecto.UUID.dump!(client_id)]
    ).rows
    |> hd()
    |> hd()
  end

  defp refresh_context do
    {:ok, generation} = Features.snapshot("segments", :franchise)
    schedule = Repo.get_by!(Schedule, kind: "segments.refresh", scope_key: "franchise")

    Repo.update_all(from(s in Schedule, where: s.id == ^schedule.id),
      set: [running: true, current_job_id: 999]
    )

    %{
      feature: "segments",
      scope: :franchise,
      generation: generation,
      schedule_id: schedule.id,
      job_id: 999
    }
  end
end
