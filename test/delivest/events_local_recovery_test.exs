defmodule Delivest.EventsLocalRecoveryTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Delivest.Repo

  import Ecto.Query
  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Events
  alias Delivest.Events.{DeliverWorker, Delivery, Event}
  alias Delivest.Identity.Branch.{BranchInfo, LoyaltySettings}
  alias Delivest.Integrations.Crm.{BranchSettings, CommandWorker}
  alias Delivest.Integrations.Crm.{CommandDelivery, SyncWorker}
  alias Delivest.Integrations.Crm
  alias Delivest.Integrations.TestCrm
  alias Delivest.Loyalty.Entry
  alias Delivest.Oms.Kitchen.SendWorker
  alias Delivest.Oms.Order
  alias Delivest.Push.NoteWorker
  alias Delivest.Repo

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    branch = insert(:branch)

    on_exit(fn ->
      Application.delete_env(:delivest, :test_crm_barrier)
      Application.delete_env(:delivest, :test_crm_idempotent)
      Application.delete_env(:delivest, :test_crm_observer)
      cleanup_branch(branch.id)
      Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
    end)

    {:ok, branch: branch}
  end

  test "push removed-items job survives kill around delivery commit", %{branch: branch} do
    branch_info(branch, %{})
    order = order_fixture(branch.id)
    deliver_events()

    {:ok, event} =
      Events.record(
        "order.updated",
        order,
        %{
          "changes" => %{
            "items" => %{"from" => [%{"title" => "Soup", "quantity" => 1}], "to" => []}
          }
        },
        %{"kind" => "staff"}
      )

    job = delivery_job(event, "push")
    kill_before_commit(job, fn -> job_count(NoteWorker, event.id) end)
    assert job_count(NoteWorker, event.id) == 0
    assert_once_after_kill(job)
    assert job_count(NoteWorker, event.id) == 1
  end

  test "kitchen scheduled send survives kill around delivery commit", %{branch: branch} do
    branch_info(branch, %{kitchen: %{enabled: true, lead_minutes: 90}})
    order = order_fixture(branch.id)
    deliver_events()

    at = DateTime.utc_now() |> DateTime.add(120, :minute) |> DateTime.truncate(:second)
    order = order |> Ecto.Changeset.change(status: :accepted, cook_by: at) |> Repo.update!()

    {:ok, event} =
      Events.record(
        "order.status_changed",
        order,
        %{"from" => "created", "to" => "accepted"},
        %{}
      )

    job = delivery_job(event, "kitchen")
    kill_before_commit(job, fn -> order_job_count(SendWorker, order.id) end)
    assert order_job_count(SendWorker, order.id) == 0
    assert_once_after_kill(job)
    assert order_job_count(SendWorker, order.id) == 1
  end

  test "loyalty accrual survives kill around delivery commit", %{branch: branch} do
    branch_info(branch, %{
      loyalty: %LoyaltySettings{enabled: true, per_rubles: 100, stars: 5, expire_days: 180}
    })

    client = insert(:client, phone: "+79991112233")

    order =
      branch.id
      |> order_fixture(price: 25_000, attrs: %{"customer_phone" => client.phone})
      |> Ecto.Changeset.change(client_id: client.id, status: :completed)
      |> Repo.update!()

    deliver_events()

    {:ok, event} =
      Events.record("order.status_changed", order, %{"from" => "ready", "to" => "completed"}, %{})

    job = delivery_job(event, "loyalty")

    kill_before_commit(job, fn ->
      Repo.aggregate(
        from(e in Entry, where: e.order_id == ^order.id and e.kind == :accrual),
        :count
      )
    end)

    assert Repo.aggregate(
             from(e in Entry, where: e.order_id == ^order.id and e.kind == :accrual),
             :count
           ) == 0

    assert_once_after_kill(job)

    assert Repo.aggregate(
             from(e in Entry, where: e.order_id == ^order.id and e.kind == :accrual),
             :count
           ) == 1
  end

  test "crm command enqueue survives kill around delivery commit", %{branch: branch} do
    branch_info(branch, %{
      crm: %BranchSettings{
        enabled: true,
        provider: :test_crm,
        test_crm: %TestCrm.Settings{token: "t"}
      }
    })

    order = order_fixture(branch.id)
    deliver_events()

    order =
      order
      |> Order.crm_changeset(%{provider: "test_crm", status: "sent"})
      |> Repo.update!()

    {:ok, event} =
      Events.record(
        "order.updated",
        order,
        %{"changes" => %{"comment" => %{"from" => nil, "to" => "new"}}},
        %{"kind" => "staff"}
      )

    job = delivery_job(event, "crm")
    kill_before_commit(job, fn -> job_count(CommandWorker, event.id) end)
    assert job_count(CommandWorker, event.id) == 0
    assert_once_after_kill(job)
    assert job_count(CommandWorker, event.id) == 1
  end

  test "opposite completed and cancelled events use database sequence even with descending UUIDs",
       %{branch: branch} do
    branch_info(branch, %{
      loyalty: %LoyaltySettings{enabled: true, per_rubles: 100, stars: 5, expire_days: 180}
    })

    client = insert(:client)

    order =
      branch.id
      |> order_fixture(price: 25_000, attrs: %{"customer_phone" => client.phone})
      |> Ecto.Changeset.change(client_id: client.id, status: :cancelled)
      |> Repo.update!()

    deliver_events()

    suffix = Ecto.UUID.generate() |> String.slice(-12, 12)

    first =
      Repo.insert!(%Event{
        id: "ffffffff-ffff-4fff-8fff-#{suffix}",
        type: "order.status_changed",
        aggregate_type: "order",
        aggregate_id: order.id,
        branch_id: branch.id,
        payload: %{"from" => "ready", "to" => "completed"}
      })

    second =
      Repo.insert!(%Event{
        id: "00000000-0000-4000-8000-#{suffix}",
        type: "order.status_changed",
        aggregate_type: "order",
        aggregate_id: order.id,
        branch_id: branch.id,
        payload: %{"from" => "completed", "to" => "cancelled"}
      })

    for event <- [first, second] do
      Repo.insert!(%Delivery{event_id: event.id, subscriber: "loyalty"})

      {:ok, _job} =
        %{event_id: event.id, subscriber: "loyalty"} |> DeliverWorker.new() |> Oban.insert()
    end

    assert first.sequence < second.sequence
    assert first.id > second.id
    assert {:snooze, 5} = DeliverWorker.perform(delivery_job(second, "loyalty"))
    assert :ok = DeliverWorker.perform(delivery_job(first, "loyalty"))
    assert :ok = DeliverWorker.perform(delivery_job(second, "loyalty"))

    assert Repo.aggregate(
             from(e in Entry, where: e.order_id == ^order.id and e.kind == :accrual),
             :count
           ) == 1

    assert Repo.aggregate(
             from(e in Entry, where: e.order_id == ^order.id and e.kind == :accrual_reversal),
             :count
           ) == 1

    assert Delivest.Loyalty.balance(client.id) == 0
  end

  test "simultaneous loyalty accrual calls create one cycle and one balance change", %{
    branch: branch
  } do
    branch_info(branch, %{
      loyalty: %LoyaltySettings{enabled: true, per_rubles: 100, stars: 5, expire_days: 180}
    })

    client = insert(:client)

    order =
      branch.id
      |> order_fixture(price: 25_000, attrs: %{"customer_phone" => client.phone})
      |> Ecto.Changeset.change(client_id: client.id)
      |> Repo.update!()

    results =
      1..2
      |> Task.async_stream(fn _ -> Delivest.Loyalty.accrue(order) end,
        max_concurrency: 2,
        timeout: :infinity
      )
      |> Enum.to_list()

    assert Enum.count(results, &match?({:ok, {:ok, %Entry{}}}, &1)) == 1
    assert Enum.count(results, &match?({:ok, {:ok, nil}}, &1)) == 1
    assert Delivest.Loyalty.balance(client.id) == 10
  end

  test "delivery diagnostics require branch order permission and resolve an explicit blocked event",
       %{branch: branch} do
    branch_info(branch, %{})
    order = order_fixture(branch.id)
    deliver_events()

    event =
      Repo.insert!(%Event{
        type: "order.status_changed",
        aggregate_type: "order",
        aggregate_id: order.id,
        branch_id: branch.id,
        payload: %{"to" => "completed"}
      })

    Repo.insert!(%Delivery{event_id: event.id, subscriber: "loyalty", status: "blocked"})
    staff = operator(branch)

    outsider =
      insert(:staff, role: build(:role, permissions: []), branches: [branch])
      |> Repo.preload([:role, :branches])

    assert {:error, :forbidden} = Events.list_blocked(outsider, branch.id)

    assert {:error, :forbidden} =
             Events.resolve_delivery(outsider, branch.id, event.id, "loyalty", "done")

    assert {:error, :forbidden} = Crm.list_unknown_commands(outsider, branch.id)
    assert {:error, :forbidden} = Crm.resolve_command(outsider, branch.id, 1, "done")

    assert {:ok, [%{event_id: id, subscriber: "loyalty"}]} = Events.list_blocked(staff, branch.id)
    assert id == event.id

    assert {:error, :invalid_event_id} =
             Events.resolve_delivery(staff, branch.id, "bad", "loyalty", "done")

    assert {:error, :invalid_action} =
             Events.resolve_delivery(staff, branch.id, event.id, "loyalty", "skip")

    assert {:ok, %Delivery{status: "delivered"}} =
             Events.resolve_delivery(staff, branch.id, event.id, "loyalty", "done")

    assert {:ok, []} = Events.list_blocked(staff, branch.id)

    another =
      Repo.insert!(%Event{
        type: "order.status_changed",
        aggregate_type: "order",
        aggregate_id: order.id,
        branch_id: branch.id,
        payload: %{"to" => "completed"}
      })

    Repo.insert!(%Delivery{event_id: another.id, subscriber: "loyalty", status: "blocked"})

    {:ok, retry_job} =
      %{event_id: another.id, subscriber: "loyalty"} |> DeliverWorker.new() |> Oban.insert()

    Repo.update_all(from(j in Oban.Job, where: j.id == ^retry_job.id), set: [state: "cancelled"])

    assert {:ok, %Delivery{status: "pending"}} =
             Events.resolve_delivery(staff, branch.id, another.id, "loyalty", "retry")

    assert Repo.get!(Oban.Job, retry_job.id).state == "available"
  end

  test "operator can explicitly retry an uncertain crm command", %{branch: branch} do
    branch_info(branch, crm_settings())
    order = order_fixture(branch.id)
    deliver_events()

    order =
      order |> Order.crm_changeset(%{provider: "test_crm", status: "sent"}) |> Repo.update!()

    staff = operator(branch)

    {:ok, job} = Crm.enqueue_command(order, "update", %{"changes" => %{"comment" => %{}}})

    Repo.update_all(from(d in CommandDelivery, where: d.job_id == ^job.id),
      set: [phase: "unknown"]
    )

    Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id), set: [state: "discarded"])

    assert {:ok, %CommandDelivery{phase: "pending"}} =
             Crm.resolve_command(staff, branch.id, job.id, "retry")

    assert Repo.get!(Oban.Job, job.id).state == "available"
    assert :ok = CommandWorker.perform(job)
    assert Repo.get!(CommandDelivery, job.id).phase == "done"
  end

  test "operator retries a pruned uncertain command at its original sequence position", %{
    branch: branch
  } do
    branch_info(branch, crm_settings())
    order = order_fixture(branch.id)
    deliver_events()

    order =
      order
      |> Order.crm_changeset(%{provider: "test_crm", status: "sent"})
      |> Repo.update!()

    staff = operator(branch)
    first_changes = %{"comment" => %{"to" => "first"}}
    second_changes = %{"address" => %{"to" => "second"}}
    {:ok, first} = Crm.enqueue_command(order, "update", %{"changes" => first_changes})
    {:ok, second} = Crm.enqueue_command(order, "update", %{"changes" => second_changes})
    Application.put_env(:delivest, :test_crm_barrier, %{owner: self(), action: :update})

    {pid, ref} = spawn_monitor(fn -> CommandWorker.perform(first) end)

    assert_receive {:crm_remote_success, ^pid, :update, {:update, order_id, ^first_changes}},
                   5_000

    assert order_id == order.id
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 5_000
    Application.delete_env(:delivest, :test_crm_barrier)

    stale = DateTime.add(DateTime.utc_now(), -601, :second)

    Repo.update_all(from(d in CommandDelivery, where: d.job_id == ^first.id),
      set: [updated_at: stale]
    )

    assert {:cancel, :unknown_outcome} = CommandWorker.perform(first)
    Repo.delete!(Repo.get!(Oban.Job, first.id))
    assert {:snooze, 30} = CommandWorker.perform(second)

    assert {:ok, %CommandDelivery{job_id: original_id, execution_job_id: replacement_id}} =
             Crm.resolve_command(staff, branch.id, first.id, "retry")

    assert original_id == first.id
    assert replacement_id > second.id
    replacement = Repo.get!(Oban.Job, replacement_id)
    assert replacement.args["command_delivery_id"] == first.id
    assert replacement.args["changes"] == first_changes
    assert {:snooze, 30} = CommandWorker.perform(second)

    Application.put_env(:delivest, :test_crm_observer, self())
    assert :ok = CommandWorker.perform(replacement)
    assert_receive {:crm_call, :update, {:update, ^order_id, ^first_changes}}
    assert :ok = CommandWorker.perform(second)
    assert_receive {:crm_call, :update, {:update, ^order_id, ^second_changes}}

    assert Repo.get!(CommandDelivery, first.id).phase == "done"
    assert Repo.get!(CommandDelivery, second.id).phase == "done"
    assert Repo.aggregate(from(d in CommandDelivery, where: d.order_id == ^order.id), :count) == 2
  end

  test "pruned legacy command without stored arguments gives an explicit retry error", %{
    branch: branch
  } do
    branch_info(branch, crm_settings())
    order = order_fixture(branch.id)
    deliver_events()
    staff = operator(branch)
    {:ok, job} = Crm.enqueue_command(order, "update", %{"changes" => %{"comment" => %{}}})

    Repo.update_all(from(d in CommandDelivery, where: d.job_id == ^job.id),
      set: [phase: "unknown", args: nil]
    )

    Repo.delete!(Repo.get!(Oban.Job, job.id))

    assert {:error, :command_args_not_found} =
             Crm.resolve_command(staff, branch.id, job.id, "retry")

    assert Repo.get!(CommandDelivery, job.id).phase == "unknown"
  end

  test "non-idempotent crm sync is not replayed after remote success and kill", %{branch: branch} do
    branch_info(branch, crm_settings())
    order = order_fixture(branch.id)
    deliver_events()

    order =
      order
      |> Order.crm_changeset(%{provider: "test_crm", status: "pending"})
      |> Repo.update!()

    {:ok, job} = Crm.enqueue_sync(order)
    staff = operator(branch)
    Application.put_env(:delivest, :test_crm_idempotent, false)
    Application.put_env(:delivest, :test_crm_barrier, %{owner: self(), action: :deliver})

    {pid, ref} = spawn_monitor(fn -> SyncWorker.perform(job) end)
    assert_receive {:crm_remote_success, ^pid, :deliver, {:deliver, order_id}}, 5_000
    assert order_id == order.id
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 5_000
    Application.delete_env(:delivest, :test_crm_barrier)

    assert Repo.get!(Order, order.id).crm.status == "sending"
    assert {:snooze, 30} = SyncWorker.perform(job)

    stale = DateTime.utc_now() |> DateTime.add(-601, :second) |> DateTime.truncate(:second)
    {:ok, _} = Crm.SyncState.retrying(Repo.get!(Order, order.id), "", 1)

    {:ok, _} =
      Repo.get!(Order, order.id)
      |> Order.crm_changeset(%{status: "sending", sending_started_at: stale})
      |> Repo.update()

    assert {:cancel, :unknown_outcome} = SyncWorker.perform(job)
    assert Repo.get!(Order, order.id).crm.status == "unknown"
    refute_receive {:crm_remote_success, _, :deliver, _}, 0

    assert {:ok, _} = Crm.resolve_alert(staff, branch.id, order.id, "exists", "crm-1")
    assert Repo.get!(Order, order.id).crm.status == "sent"
  end

  test "operator list promotes stale crm sync after final worker kill without another job", %{
    branch: branch
  } do
    branch_info(branch, crm_settings())
    order = order_fixture(branch.id)
    deliver_events()

    order =
      order |> Order.crm_changeset(%{provider: "test_crm", status: "pending"}) |> Repo.update!()

    {:ok, job} = Crm.enqueue_sync(order)
    staff = operator(branch)

    outsider =
      insert(:staff, role: build(:role, permissions: []), branches: [branch])
      |> Repo.preload([:role, :branches])

    Application.put_env(:delivest, :test_crm_idempotent, false)
    Application.put_env(:delivest, :test_crm_barrier, %{owner: self(), action: :deliver})

    {pid, ref} = spawn_monitor(fn -> SyncWorker.perform(job) end)
    assert_receive {:crm_remote_success, ^pid, :deliver, {:deliver, order_id}}, 5_000
    assert order_id == order.id
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 5_000
    Application.delete_env(:delivest, :test_crm_barrier)

    Repo.delete!(Repo.get!(Oban.Job, job.id))
    stale = DateTime.utc_now() |> DateTime.add(-601, :second) |> DateTime.truncate(:second)

    {:ok, _} =
      Repo.get!(Order, order.id)
      |> Order.crm_changeset(%{sending_started_at: stale})
      |> Repo.update()

    assert {:error, :forbidden} = Crm.list_unknown_syncs(outsider, branch.id)

    assert {:ok, [%Order{id: ^order_id, crm: %{status: "unknown", alert: alert}}]} =
             Crm.list_unknown_syncs(staff, branch.id)

    assert is_binary(alert) and alert != ""
    refute_receive {:crm_remote_success, _, :deliver, _}, 0
  end

  test "crm command unknown blocks later command until operator resolves it", %{branch: branch} do
    branch_info(branch, crm_settings())
    order = order_fixture(branch.id)
    deliver_events()

    order =
      order
      |> Order.crm_changeset(%{provider: "test_crm", status: "sent"})
      |> Repo.update!()

    staff = operator(branch)
    {:ok, first} = Crm.enqueue_command(order, "update", %{"changes" => %{"comment" => %{}}})
    Application.put_env(:delivest, :test_crm_barrier, %{owner: self(), action: :update})

    {pid, ref} = spawn_monitor(fn -> CommandWorker.perform(first) end)
    assert_receive {:crm_remote_success, ^pid, :update, {:update, order_id, _changes}}, 5_000
    assert order_id == order.id
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 5_000
    Application.delete_env(:delivest, :test_crm_barrier)

    assert Repo.get!(CommandDelivery, first.id).phase == "calling"
    assert {:snooze, 30} = CommandWorker.perform(first)

    stale = DateTime.add(DateTime.utc_now(), -601, :second)

    Repo.update_all(from(d in CommandDelivery, where: d.job_id == ^first.id),
      set: [updated_at: stale]
    )

    assert {:cancel, :unknown_outcome} = CommandWorker.perform(first)
    assert Repo.get!(CommandDelivery, first.id).phase == "unknown"
    refute_receive {:crm_remote_success, _, :update, _}, 0

    {:ok, second} = Crm.enqueue_command(order, "update", %{"changes" => %{"address" => %{}}})
    assert {:snooze, 30} = CommandWorker.perform(second)
    assert {:ok, [_]} = Crm.list_unknown_commands(staff, branch.id)
    assert {:ok, _} = Crm.resolve_command(staff, branch.id, first.id, "done")
    assert :ok = CommandWorker.perform(second)
    assert Repo.get!(CommandDelivery, second.id).phase == "done"
  end

  test "crm updates run in enqueue order when workers start in reverse", %{branch: branch} do
    branch_info(branch, crm_settings())
    order = order_fixture(branch.id)
    deliver_events()

    order =
      order
      |> Order.crm_changeset(%{provider: "test_crm", status: "sent"})
      |> Repo.update!()

    {:ok, first} = Crm.enqueue_command(order, "update", %{"changes" => %{"comment" => %{}}})
    {:ok, second} = Crm.enqueue_command(order, "update", %{"changes" => %{"address" => %{}}})
    Application.put_env(:delivest, :test_crm_observer, self())

    assert {:snooze, 30} = CommandWorker.perform(second)
    refute_receive {:crm_call, _, _}, 0
    assert :ok = CommandWorker.perform(first)
    assert :ok = CommandWorker.perform(second)
    assert_receive {:crm_call, :update, {:update, order_id, %{"comment" => %{}}}}
    assert order_id == order.id
    assert_receive {:crm_call, :update, {:update, ^order_id, %{"address" => %{}}}}
  end

  defp crm_settings do
    %{
      crm: %BranchSettings{
        enabled: true,
        provider: :test_crm,
        test_crm: %TestCrm.Settings{token: "t"}
      }
    }
  end

  defp operator(branch) do
    insert(:staff, role: build(:role, permissions: ["orders.update"]), branches: [branch])
    |> Repo.preload([:role, :branches])
  end

  defp branch_info(branch, info) do
    Repo.insert!(struct(BranchInfo, Map.put(info, :branch_id, branch.id)))
    branch
  end

  defp cleanup_branch(branch_id) do
    order_ids =
      Repo.query!("SELECT id::text FROM orders WHERE branch_id = $1", [Ecto.UUID.dump!(branch_id)]).rows
      |> List.flatten()

    event_ids =
      Repo.query!("SELECT id::text FROM domain_events WHERE branch_id = $1", [
        Ecto.UUID.dump!(branch_id)
      ]).rows
      |> List.flatten()

    client_ids =
      Repo.query!(
        "SELECT DISTINCT client_id::text FROM orders WHERE branch_id = $1 AND client_id IS NOT NULL",
        [Ecto.UUID.dump!(branch_id)]
      ).rows
      |> List.flatten()

    product_ids =
      Repo.query!(
        "SELECT to_id::text FROM entity_relations WHERE from_entity_type = 'Branch' AND from_id = $1 AND to_entity_type = 'Product'",
        [Ecto.UUID.dump!(branch_id)]
      ).rows
      |> List.flatten()

    staff_roles =
      Repo.query!(
        "SELECT s.id::text, s.role_id::text FROM staff s JOIN staff_branches sb ON sb.staff_id = s.id WHERE sb.branch_id = $1",
        [Ecto.UUID.dump!(branch_id)]
      ).rows

    staff_ids = Enum.map(staff_roles, &hd/1)
    role_ids = Enum.map(staff_roles, &Enum.at(&1, 1))

    Repo.query!(
      "DELETE FROM oban_jobs WHERE args->>'branch_id' = $1 OR args->>'order_id' = ANY($2) OR args->>'event_id' = ANY($3)",
      [branch_id, order_ids, event_ids]
    )

    Repo.query!("DELETE FROM oban_jobs WHERE worker = $1 AND args->>'id' = ANY($2)", [
      Oban.Worker.to_string(Delivest.Push.StaffWorker),
      order_ids
    ])

    Repo.query!("DELETE FROM audit_events WHERE branch_id = $1", [Ecto.UUID.dump!(branch_id)])

    Repo.query!("DELETE FROM integration_requests WHERE branch_id = $1", [
      Ecto.UUID.dump!(branch_id)
    ])

    Repo.query!("DELETE FROM crm_command_deliveries WHERE branch_id = $1", [
      Ecto.UUID.dump!(branch_id)
    ])

    Repo.query!("DELETE FROM fiscal_receipts WHERE branch_id = $1", [Ecto.UUID.dump!(branch_id)])
    Repo.query!("DELETE FROM loyalty_entries WHERE branch_id = $1", [Ecto.UUID.dump!(branch_id)])
    Repo.query!("DELETE FROM domain_events WHERE branch_id = $1", [Ecto.UUID.dump!(branch_id)])
    Repo.query!("DELETE FROM orders WHERE branch_id = $1", [Ecto.UUID.dump!(branch_id)])
    Repo.query!("DELETE FROM carts WHERE branch_id = $1", [Ecto.UUID.dump!(branch_id)])
    Repo.query!("DELETE FROM order_counters WHERE branch_id = $1", [Ecto.UUID.dump!(branch_id)])

    Repo.query!(
      "DELETE FROM entity_relations WHERE from_entity_type = 'Branch' AND from_id = $1",
      [Ecto.UUID.dump!(branch_id)]
    )

    Repo.query!("DELETE FROM products WHERE id::text = ANY($1)", [product_ids])
    Repo.query!("DELETE FROM branch_info WHERE branch_id = $1", [Ecto.UUID.dump!(branch_id)])
    Repo.query!("DELETE FROM branches WHERE id = $1", [Ecto.UUID.dump!(branch_id)])
    Repo.query!("DELETE FROM staff WHERE id::text = ANY($1)", [staff_ids])
    Repo.query!("DELETE FROM roles WHERE id::text = ANY($1)", [role_ids])
    Repo.query!("DELETE FROM clients WHERE id::text = ANY($1)", [client_ids])
  end

  defp deliver_events, do: Delivest.DataCase.deliver_events()

  defp delivery_job(event, key) do
    Repo.one!(
      from(j in Oban.Job,
        where: j.worker == ^Oban.Worker.to_string(DeliverWorker),
        where: fragment("?->>'event_id' = ?", j.args, ^event.id),
        where: fragment("?->>'subscriber' = ?", j.args, ^key)
      )
    )
  end

  defp kill_before_commit(job, uncommitted_count) do
    handler_id = {__MODULE__, make_ref()}
    owner = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:delivest, :repo, :query],
        fn _event, _measurements, metadata, _config ->
          if String.contains?(metadata.query || "", "UPDATE \"event_deliveries\"") do
            send(owner, {:before_commit, self()})

            receive do
              :continue -> :ok
            end
          end
        end,
        nil
      )

    {pid, ref} = spawn_monitor(fn -> DeliverWorker.perform(job) end)
    assert_receive {:before_commit, ^pid}, 5_000
    assert uncommitted_count.() == 0
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 5_000
    :telemetry.detach(handler_id)

    assert Repo.get_by!(Delivery,
             event_id: job.args["event_id"],
             subscriber: job.args["subscriber"]
           ).status ==
             "pending"
  end

  defp assert_once_after_kill(job) do
    owner = self()

    {pid, ref} =
      spawn_monitor(fn ->
        send(owner, {:delivered, self(), DeliverWorker.perform(job)})

        receive do
          :finish -> :ok
        end
      end)

    assert_receive {:delivered, ^pid, :ok}, 5_000
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 5_000
    assert :ok = DeliverWorker.perform(job)

    assert Repo.get_by!(Delivery,
             event_id: job.args["event_id"],
             subscriber: job.args["subscriber"]
           ).status ==
             "delivered"
  end

  defp job_count(worker, event_id),
    do:
      Repo.aggregate(
        from(j in Oban.Job,
          where: j.worker == ^Oban.Worker.to_string(worker),
          where: fragment("?->>'event_id' = ?", j.args, ^event_id)
        ),
        :count
      )

  defp order_job_count(worker, order_id),
    do:
      Repo.aggregate(
        from(j in Oban.Job,
          where: j.worker == ^Oban.Worker.to_string(worker),
          where: fragment("?->>'order_id' = ?", j.args, ^order_id)
        ),
        :count
      )
end
