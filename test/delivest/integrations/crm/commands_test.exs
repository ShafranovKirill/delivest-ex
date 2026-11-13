defmodule Delivest.Integrations.Crm.CommandsTest do
  use Delivest.DataCase, async: true
  use Oban.Testing, repo: Delivest.Repo
  import Ecto.Query

  import Delivest.Factory

  alias Delivest.Events.Event
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Crm

  alias Delivest.Integrations.Crm.{
    BranchSettings,
    Command,
    CommandWorker,
    Commands,
    ConfirmWorker,
    OrderSubscriber,
    SyncWorker
  }

  alias Delivest.Integrations.{Frontpad, TestCrm}
  alias Delivest.Oms
  alias Delivest.Oms.{Carts, Order, Orders}

  setup do
    branch = insert(:branch, is_active: true)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{
        enabled: true,
        provider: :test_crm,
        test_crm: %TestCrm.Settings{token: "t"}
      }
    })

    product = insert_branch_product(branch.id, price: 100)
    {:ok, cart} = Carts.create_cart(%{session_id: "cmd-#{branch.id}", branch_id: branch.id})
    {:ok, _, _} = Carts.add_item(cart.id, product.id, 1)

    {:ok, order} =
      Oms.create_order(%{
        "cart_id" => cart.id,
        "branch_id" => branch.id,
        "fulfillment_type" => "pickup",
        "payment_method" => "cash"
      })

    %{order: order}
  end

  defp sync(order),
    do:
      perform_job(SyncWorker, %{
        "order_id" => order.id,
        "branch_id" => order.branch_id,
        "generation" => Crm.get_branch_settings(order.branch_id).generation
      })

  defp sent(order) do
    :ok = sync(order)
    Orders.get_order(order.id)
  end

  test "providers report capabilities and idempotency" do
    assert Crm.capabilities(:frontpad) == []
    refute Crm.idempotent?(:frontpad)
    assert :cancel in Crm.capabilities(:test_crm)
    assert Crm.idempotent?(:test_crm)
    assert Crm.status_for(:test_crm, nil, 9) == :cancelled

    assert Crm.status_for(
             :frontpad,
             %Frontpad.Settings{statuses: %Frontpad.StatusCodes{ready: "3"}},
             "3"
           ) ==
             :ready
  end

  test "dictionaries come from the active provider", %{order: order} do
    assert {:ok, %{payment_types: [%{id: "cash"}]}} = Crm.dictionaries(order.branch_id)
  end

  test "a pending creation waits for confirmation", %{order: order} do
    Process.put({TestCrm, :deliver}, {:pending, "ref-1"})
    :ok = sync(order)

    order = Orders.get_order(order.id)
    assert %{status: "confirming", ref: "ref-1"} = order.crm
    assert order.status == :created
    assert_enqueued(worker: ConfirmWorker, args: %{"order_id" => order.id})

    assert {:ok, %Order{status: :accepted, crm: %{status: "sent", external_id: "e-9"}}} =
             Crm.confirm_order(order, %{external_id: "e-9"})
  end

  test "an unconfirmed idempotent creation is sent again", %{order: order} do
    Process.put({TestCrm, :deliver}, {:pending, "ref-1"})
    :ok = sync(order)

    :ok = perform_job(ConfirmWorker, %{"order_id" => order.id})
    assert %{status: "pending"} = Orders.get_order(order.id).crm
    assert_enqueued(worker: SyncWorker, args: %{"order_id" => order.id})
  end

  test "an unconfirmed creation remains visible when sending is disabled before retry", %{
    order: order
  } do
    Process.put({TestCrm, :deliver}, {:pending, "ref-1"})
    :ok = sync(order)
    branch = Repo.get!(Delivest.Identity.Branch, order.branch_id)
    staff = insert(:staff, role: insert(:role, permissions: ["integrations.update"]))
    insert(:staff_branch, staff: staff, branch: branch)

    assert {:ok, _} = Crm.update_branch_settings(staff, branch.id, %{"enabled" => false})
    assert :ok = perform_job(ConfirmWorker, %{"order_id" => order.id})
    assert %{status: "unknown", alert: alert} = Orders.get_order(order.id).crm
    assert is_binary(alert)
    refute_enqueued(worker: SyncWorker, args: %{"order_id" => order.id})
  end

  test "a rejected creation fails the sync", %{order: order} do
    Process.put({TestCrm, :deliver}, {:pending, "ref-1"})
    :ok = sync(order)

    assert {:ok, %Order{crm: %{status: "failed", last_error: "bad"}}} =
             Crm.reject_order(Orders.get_order(order.id), "bad")
  end

  test "a cancel goes to a crm that can cancel", %{order: order} do
    order = sent(order)
    {:ok, _order} = Orders.cancel_order(order, :system, %{"cancel_reason" => "out_of_stock"})

    cancel_event =
      Repo.one!(
        from(e in Event,
          where: e.aggregate_id == ^order.id and e.type == "order.cancelled",
          order_by: [desc: e.inserted_at],
          limit: 1
        )
      )

    assert {:ok, _} = OrderSubscriber.handle(cancel_event)

    assert_enqueued(worker: CommandWorker, args: %{"action" => "cancel", "order_id" => order.id})

    command = Repo.get_by!(Command, order_id: order.id, action: "cancel")
    assert :ok = CommandWorker.perform(%{Repo.get!(Oban.Job, command.job_id) | attempt: 1})

    assert_received {:cancel, _id, :out_of_stock}
    refute Crm.manual_cancel_required?(%{order | channel: %{remote_status: "cancelled"}})
  end

  test "only allowed changes go to the crm", %{order: order} do
    order = sent(order)

    event = %Event{
      type: "order.updated",
      aggregate_id: order.id,
      actor: %{"kind" => "staff"},
      payload: %{
        "changes" => %{
          "comment" => %{"from" => nil, "to" => "x"},
          "items" => %{"from" => [], "to" => []}
        }
      }
    }

    {:ok, _job} = OrderSubscriber.handle(event)

    assert_enqueued(
      worker: CommandWorker,
      args: %{"action" => "update", "changes" => %{"comment" => %{"from" => nil, "to" => "x"}}}
    )

    assert :ok = OrderSubscriber.handle(%{event | actor: %{"kind" => "crm"}})
  end

  test "failed commands stop on permanent errors", %{order: order} do
    order = sent(order)
    Process.put({TestCrm, :update}, {:error, :rejected})

    {:ok, job} = Crm.enqueue_command(order, "update", %{"changes" => %{}})
    assert {:cancel, :rejected} = CommandWorker.perform(%{job | attempt: 1})
  end

  test "stable event identity deduplicates enqueue and preserves ordering", %{order: order} do
    order = sent(order)

    event_id =
      Repo.one!(from(e in Event, where: e.aggregate_id == ^order.id, limit: 1, select: e.id))

    {:ok, first} = Crm.enqueue_command(order, "update", %{"changes" => %{}}, event_id)
    {:ok, duplicate} = Crm.enqueue_command(order, "update", %{"changes" => %{}}, event_id)
    {:ok, later} = Crm.enqueue_command(order, "cancel", %{"reason" => "out_of_stock"})

    assert first.id == duplicate.id
    assert Repo.get_by!(Command, job_id: first.id).id < Repo.get_by!(Command, job_id: later.id).id
    assert {:snooze, 5} = CommandWorker.perform(%{later | attempt: 1})
    assert :ok = CommandWorker.perform(%{first | attempt: 1})
    assert :ok = CommandWorker.perform(%{later | attempt: 1})
  end

  test "two updates reach CRM in enqueue order", %{order: order} do
    order = sent(order)
    first_changes = %{"comment" => %{"from" => nil, "to" => "first"}}
    second_changes = %{"comment" => %{"from" => "first", "to" => "second"}}
    {:ok, first} = Crm.enqueue_command(order, "update", %{"changes" => first_changes})
    {:ok, second} = Crm.enqueue_command(order, "update", %{"changes" => second_changes})

    assert {:snooze, 5} = CommandWorker.perform(%{second | attempt: 1})
    assert :ok = CommandWorker.perform(%{first | attempt: 1})
    assert_received {:update, _, ^first_changes}
    assert :ok = CommandWorker.perform(%{second | attempt: 1})
    assert_received {:update, _, ^second_changes}
  end

  test "crash after claim leaves unknown and blocks later commands", %{order: order} do
    order = sent(order)
    {:ok, first} = Crm.enqueue_command(order, "update", %{"changes" => %{}})
    {:ok, later} = Crm.enqueue_command(order, "cancel", %{"reason" => "out_of_stock"})
    assert {:claimed, command, _token} = Commands.claim(%{first | attempt: 1})

    assert {:cancel, :unknown_outcome} = CommandWorker.perform(%{first | attempt: 2})
    assert Repo.reload!(command).status == "unknown"
    assert {:snooze, 5} = CommandWorker.perform(%{later | attempt: 1})
    refute_received {:update, _, _}
    refute_received {:cancel, _, _}
  end

  test "legacy job id bridges to its backfilled command", %{order: order} do
    order = sent(order)
    args = %{"order_id" => order.id, "action" => "update", "changes" => %{}}
    {:ok, job} = args |> CommandWorker.new() |> Oban.insert()

    Repo.insert!(%Command{
      order_id: order.id,
      provider: to_string(order.crm.provider),
      action: "update",
      args: %{"changes" => %{}},
      job_id: job.id
    })

    assert :ok = CommandWorker.perform(%{job | attempt: 1})
    assert_received {:update, _, _}
  end

  test "manual recovery requires admin, reason and confirmed absence", %{order: order} do
    order = sent(order)
    {:ok, job} = Crm.enqueue_command(order, "update", %{"changes" => %{}})
    assert {:claimed, command, _token} = Commands.claim(%{job | attempt: 1})
    assert {:cancel, :unknown_outcome} = CommandWorker.perform(%{job | attempt: 2})

    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))
    reader = insert(:staff, role: insert(:role, permissions: ["orders.read"]))

    assert {:error, :forbidden} = Commands.resolve(command.id, reader.id, "checked", :retry, true)

    assert {:error, :actor_and_reason_required} =
             Commands.resolve(command.id, admin.id, " ", :retry, true)

    assert {:error, :confirmed_absent_required} =
             Commands.resolve(command.id, admin.id, "checked", :retry)

    assert {:error, :active_job} = Commands.resolve(command.id, admin.id, "checked", :retry, true)
    Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id), set: [state: "cancelled"])
    assert {:ok, :ok} = Commands.resolve(command.id, admin.id, "checked", :retry, true)
    assert Repo.reload!(command).status == "pending"
  end

  test "duplicate with pruned job remains deduplicated", %{order: order} do
    order = sent(order)

    event_id =
      Repo.one!(from(e in Event, where: e.aggregate_id == ^order.id, limit: 1, select: e.id))

    {:ok, job} = Crm.enqueue_command(order, "update", %{"changes" => %{}}, event_id)
    command = Repo.get_by!(Command, event_id: event_id, action: "update")
    Repo.delete!(job)

    assert {:ok, %Command{id: id}} =
             Crm.enqueue_command(order, "update", %{"changes" => %{}}, event_id)

    assert id == command.id
    assert Repo.aggregate(Command, :count, :id) == 1
  end

  test "stale job cannot claim after confirmed-absent retry", %{order: order} do
    order = sent(order)
    {:ok, old_job} = Crm.enqueue_command(order, "update", %{"changes" => %{}})
    assert {:claimed, command, _} = Commands.claim(%{old_job | attempt: 1})
    assert {:cancel, :unknown_outcome} = CommandWorker.perform(%{old_job | attempt: 2})
    Repo.update_all(from(j in Oban.Job, where: j.id == ^old_job.id), set: [state: "cancelled"])
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))
    assert {:ok, :ok} = Commands.resolve(command.id, admin.id, "remote absent", :retry, true)

    assert {:blocked, "stale_job"} = Commands.claim(%{old_job | attempt: 3})
    new_job = Repo.get!(Oban.Job, Repo.reload!(command).job_id)
    assert {:claimed, _, _} = Commands.claim(%{new_job | attempt: 1})
  end

  test "deleted admin cannot resolve an unknown command", %{order: order} do
    order = sent(order)
    {:ok, job} = Crm.enqueue_command(order, "update", %{"changes" => %{}})
    assert {:claimed, command, _} = Commands.claim(%{job | attempt: 1})
    assert {:cancel, :unknown_outcome} = CommandWorker.perform(%{job | attempt: 2})
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))
    admin |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second)) |> Repo.update!()

    assert {:error, :forbidden} =
             Commands.resolve(command.id, admin.id, "checked", :confirmed_effect)
  end

  test "update then cancel during initial sync wait and later reach CRM in order", %{order: order} do
    assert order.crm.status == "pending"

    event_id =
      Repo.one!(from(e in Event, where: e.aggregate_id == ^order.id, limit: 1, select: e.id))

    update_event = %Event{
      id: event_id,
      type: "order.updated",
      aggregate_id: order.id,
      actor: %{"kind" => "staff"},
      payload: %{"changes" => %{"comment" => %{"from" => nil, "to" => "later"}}}
    }

    assert {:ok, update_job} = OrderSubscriber.handle(update_event)

    {:ok, cancelled} =
      Orders.cancel_order(order, :system, %{"cancel_reason" => "out_of_stock"})

    cancel_event =
      %Event{
        id: event_id,
        type: "order.cancelled",
        aggregate_id: order.id,
        actor: %{"kind" => "staff"},
        payload: %{}
      }

    assert {:ok, cancel_job} = OrderSubscriber.handle(cancel_event)
    assert {:snooze, 15} = CommandWorker.perform(%{update_job | attempt: 1})
    assert {:snooze, 5} = CommandWorker.perform(%{cancel_job | attempt: 1})

    :ok = sync(cancelled)
    assert :ok = CommandWorker.perform(%{update_job | attempt: 1})
    assert_received {:update, _, _}
    assert :ok = CommandWorker.perform(%{cancel_job | attempt: 1})
    assert_received {:cancel, _, :out_of_stock}
  end

  test "awaiting payment before created event does not enqueue a CRM command", %{order: order} do
    Repo.delete_all(from(e in Event, where: e.aggregate_id == ^order.id))
    order = order |> Ecto.Changeset.change(awaiting_payment: true) |> Repo.update!()

    assert :ok =
             OrderSubscriber.handle(%Event{
               type: "order.cancelled",
               aggregate_id: order.id,
               actor: %{"kind" => "staff"},
               payload: %{}
             })

    assert Repo.aggregate(Command, :count, :id) == 0
  end
end
