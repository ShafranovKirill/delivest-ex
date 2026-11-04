defmodule Delivest.Oms.KitchenTest do
  use Delivest.DataCase, async: true
  use Oban.Testing, repo: Delivest.Repo

  import Delivest.Factory
  import Delivest.OrderFixtures
  import Ecto.Query

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Oms.{Kitchen, Order, Orders, OrderTransition}
  alias Delivest.Oms.Kitchen.{OrderSubscriber, ReadyWorker, SendWorker}

  defp branch(kitchen) do
    branch = insert(:branch)
    Repo.insert!(%BranchInfo{branch_id: branch.id, kitchen: kitchen})
    branch
  end

  defp kitchen_branch, do: branch(%{enabled: true, lead_minutes: 90})

  defp staff(permissions, branch) do
    insert(:staff, role: build(:role, permissions: permissions), branches: [branch])
    |> Repo.preload([:role, :branches])
  end

  defp order(branch, changes) do
    branch.id
    |> order_fixture()
    |> Ecto.Changeset.change(changes)
    |> Repo.update!()
  end

  defp in_minutes(minutes),
    do:
      DateTime.utc_now()
      |> DateTime.add(minutes, :minute)
      |> DateTime.truncate(:second)

  defp operator(branch), do: {:staff, staff(["orders.update"], branch)}

  defp send_job(order_id) do
    Oban.Job
    |> where([j], j.worker == ^Oban.Worker.to_string(SendWorker))
    |> where([j], j.state in ["available", "scheduled", "retryable"])
    |> where([j], fragment("?->>'order_id' = ?", j.args, ^order_id))
    |> Repo.one()
  end

  describe "sending to the kitchen" do
    test "an order for now goes to the kitchen when it is confirmed" do
      branch = kitchen_branch()
      order = order(branch, [])

      assert {:ok, %Order{status: :accepted}} =
               Orders.advance_order(order, :accepted, operator(branch))

      deliver_events()
      assert Repo.reload!(order).status == :preparing

      assert [{:created, :accepted, :staff}, {:accepted, :preparing, :system}] =
               transitions(order)
    end

    test "an order for later is scheduled for the lead time" do
      branch = kitchen_branch()
      later = order(branch, cook_by: in_minutes(120))
      soon = order(branch, cook_by: in_minutes(80))

      assert {:ok, %Order{status: :accepted}} =
               Orders.advance_order(later, :accepted, operator(branch))

      assert {:ok, %Order{status: :accepted}} =
               Orders.advance_order(soon, :accepted, operator(branch))

      deliver_events()
      assert Repo.reload!(soon).status == :preparing
      assert Repo.reload!(later).status == :accepted

      job = send_job(later.id)
      assert DateTime.diff(job.scheduled_at, DateTime.utc_now(), :minute) in 29..30

      assert {:snooze, seconds} = Kitchen.send_due(later.id)
      assert seconds > 0
      assert Repo.reload!(later).status == :accepted

      Kitchen.dispatch_due(DateTime.add(DateTime.utc_now(), 31, :minute))
      assert Repo.reload!(later).status == :preparing
    end

    test "moving the cooking time replans the send" do
      branch = kitchen_branch()
      order = order(branch, cook_by: in_minutes(120))

      assert {:ok, %Order{status: :accepted}} =
               Orders.advance_order(order, :accepted, operator(branch))

      deliver_events()
      before = send_job(order.id)

      order
      |> Ecto.Changeset.change(cook_by: in_minutes(100))
      |> Repo.update!()

      assert {:ok, %Order{}} =
               OrderSubscriber.handle(%{
                 type: "order.updated",
                 aggregate_id: order.id,
                 payload: %{"changes" => %{"cook_by" => %{}}}
               })

      after_update = send_job(order.id)
      assert DateTime.compare(after_update.scheduled_at, before.scheduled_at) == :lt
      assert after_update.id == before.id
    end

    test "a repeated event keeps the same planned send" do
      branch = kitchen_branch()
      order = order(branch, cook_by: in_minutes(120))

      assert {:ok, %Order{status: :accepted}} =
               Orders.advance_order(order, :accepted, operator(branch))

      deliver_events()
      job = send_job(order.id)

      assert {:ok, %Order{}} =
               OrderSubscriber.handle(%{
                 type: "order.updated",
                 aggregate_id: order.id,
                 payload: %{"changes" => %{"cook_by" => %{}}}
               })

      assert send_job(order.id).id == job.id
    end

    test "dispatch and the worker send the order once" do
      branch = kitchen_branch()
      order = order(branch, cook_by: in_minutes(120))

      assert {:ok, %Order{status: :accepted}} =
               Orders.advance_order(order, :accepted, operator(branch))

      deliver_events()
      assert send_job(order.id)

      order |> Ecto.Changeset.change(cook_by: in_minutes(-1)) |> Repo.update!()

      assert :ok = Kitchen.dispatch_due()
      assert :ok = perform_job(SendWorker, %{order_id: order.id})
      assert Repo.reload!(order).status == :preparing

      assert Enum.count(transitions(order), &match?({_, :preparing, _}, &1)) == 1
    end

    test "leaving accepted drops the planned send" do
      branch = kitchen_branch()
      order = order(branch, cook_by: in_minutes(120))

      assert {:ok, %Order{status: :accepted}} =
               Orders.advance_order(order, :accepted, operator(branch))

      deliver_events()
      assert send_job(order.id)

      order |> Ecto.Changeset.change(status: :cancelled) |> Repo.update!()

      assert :ok =
               OrderSubscriber.handle(%{
                 type: "order.status_changed",
                 aggregate_id: order.id,
                 payload: %{}
               })

      assert send_job(order.id) == nil
    end

    test "turning the kitchen off drops planned sends" do
      branch = kitchen_branch()
      order = order(branch, cook_by: in_minutes(120))

      assert {:ok, %Order{status: :accepted}} =
               Orders.advance_order(order, :accepted, operator(branch))

      deliver_events()
      assert send_job(order.id)

      BranchInfo
      |> Repo.get_by!(branch_id: branch.id)
      |> Ecto.Changeset.change(kitchen: %{enabled: false})
      |> Repo.update!()

      Cachex.clear(:branch_cache)
      assert :ok = Kitchen.reschedule_branch(branch.id)
      assert send_job(order.id) == nil
      assert Repo.reload!(order).status == :accepted
    end

    test "nothing moves without a working kitchen" do
      off = branch(%{enabled: false})
      order = order(off, [])

      assert {:ok, %Order{status: :accepted}} =
               Orders.advance_order(order, :accepted, operator(off))

      Kitchen.dispatch_due()
      assert Repo.reload!(order).status == :accepted
    end

    test "a branch on a crm has no kitchen" do
      branch = insert(:branch)

      Repo.insert!(%BranchInfo{
        branch_id: branch.id,
        kitchen: %{enabled: true},
        crm: %{enabled: true, provider: :frontpad, frontpad: %{api_key: "key"}}
      })

      refute Kitchen.working?(branch.id)
    end
  end

  describe "the screen" do
    test "lists cooking orders by urgency and upcoming orders of the next hour" do
      branch = kitchen_branch()
      late = order(branch, status: :preparing, cook_by: in_minutes(10))
      early = order(branch, status: :preparing, cook_by: in_minutes(-5))
      upcoming = order(branch, status: :accepted, cook_by: in_minutes(120))
      _far = order(branch, status: :accepted, cook_by: in_minutes(200))

      assert [%{order: %{id: first}}, %{order: %{id: second}}] = Kitchen.list_cooking(branch.id)
      assert [first, second] == [early.id, late.id]

      assert [%{order: %{id: id}, sends_at: %DateTime{}}] =
               Kitchen.list_upcoming(branch.id, Kitchen.working(branch.id), DateTime.utc_now())

      assert id == upcoming.id
      assert [%{id: ^first}] = Kitchen.list_late(branch.id)
    end
  end

  describe "ready" do
    test "the order turns ready only after the undo window" do
      branch = kitchen_branch()
      cook = staff(["orders.cook"], branch)
      order = order(branch, status: :preparing)
      Kitchen.subscribe(branch.id)

      assert {:ok, _order} = Kitchen.mark_ready(cook, branch.id, order.id)
      assert Repo.reload!(order).status == :preparing
      assert Map.has_key?(Kitchen.pending_ready(branch.id), order.id)
      assert_enqueued(worker: ReadyWorker, args: %{order_id: order.id})

      assert :ok = perform_job(ReadyWorker, %{order_id: order.id, staff_id: cook.id})
      assert Repo.reload!(order).status == :ready
      assert_receive {:kitchen_order_ready, %Order{id: id}}
      assert id == order.id
      assert List.last(transitions(order)) == {:preparing, :ready, :staff}
    end

    test "undo cancels the pending step" do
      branch = kitchen_branch()
      cook = staff(["orders.cook"], branch)
      order = order(branch, status: :preparing)

      {:ok, _order} = Kitchen.mark_ready(cook, branch.id, order.id)
      assert :ok = Kitchen.undo_ready(cook, branch.id, order.id)
      assert Kitchen.pending_ready(branch.id) == %{}
      assert {:error, :too_late} = Kitchen.undo_ready(cook, branch.id, order.id)
      assert Repo.reload!(order).status == :preparing
    end

    test "someone without kitchen rights cannot mark ready" do
      branch = kitchen_branch()
      courier = staff(["orders.read"], branch)
      order = order(branch, status: :preparing)

      assert {:error, :forbidden} = Kitchen.mark_ready(courier, branch.id, order.id)
    end

    test "a cancelled order is not made ready" do
      branch = kitchen_branch()
      cook = staff(["orders.cook"], branch)
      order = order(branch, status: :preparing)

      {:ok, _order} = Kitchen.mark_ready(cook, branch.id, order.id)
      Repo.update!(Ecto.Changeset.change(order, status: :cancelled, cancel_reason: :other))

      assert {:cancel, :finished} =
               perform_job(ReadyWorker, %{order_id: order.id, staff_id: cook.id})
    end
  end

  describe "access" do
    test "needs branch access, orders.cook and our own enabled kitchen" do
      branch = kitchen_branch()
      cook = staff(["orders.cook"], branch)

      assert Kitchen.available?(cook, branch.id)
      assert Kitchen.unavailable_reason(branch.id) == nil

      refute Kitchen.available?(staff(["orders.read"], branch), branch.id)
      refute Kitchen.available?(staff(["orders.cook"], insert(:branch)), branch.id)

      assert Kitchen.unavailable_reason(branch(%{enabled: false}).id) == :disabled
      assert Kitchen.unavailable_reason(branch(%{enabled: true, lead_minutes: 30}).id) == nil
    end

    test "a crm kitchen is never available, even when enabled" do
      branch = insert(:branch)

      Repo.insert!(%BranchInfo{
        branch_id: branch.id,
        kitchen: %{enabled: true},
        crm: %{enabled: true, provider: :frontpad, frontpad: %{api_key: "key"}}
      })

      assert Kitchen.unavailable_reason(branch.id) == :crm
      refute Kitchen.available?(staff(["admin"], branch), branch.id)
    end

    test "a branch change notifies open kitchen sessions" do
      branch = kitchen_branch()
      admin = staff(["admin"], branch)
      Kitchen.subscribe_availability(branch.id)

      assert {:ok, _branch} =
               Delivest.Identity.update_branch(admin, branch, %{}, %{
                 "kitchen" => %{"enabled" => false}
               })

      assert_receive {:kitchen_availability, branch_id}
      assert branch_id == branch.id
      refute Kitchen.available?(staff(["orders.cook"], branch), branch.id)
    end
  end

  describe "a kitchen that was switched off" do
    test "stale commands and the delayed worker leave orders alone" do
      branch = kitchen_branch()
      cook = staff(["orders.cook"], branch)
      order = order(branch, status: :preparing)

      assert {:ok, _order} = Kitchen.mark_ready(cook, branch.id, order.id)
      set_kitchen(branch, false)

      assert {:error, :kitchen_unavailable} = Kitchen.undo_ready(cook, branch.id, order.id)
      assert {:error, :kitchen_unavailable} = Kitchen.finish_ready(order.id, cook.id)

      assert {:cancel, :kitchen_unavailable} =
               perform_job(ReadyWorker, %{order_id: order.id, staff_id: cook.id})

      assert Repo.reload!(order).status == :preparing

      set_kitchen(branch, true)
      assert Repo.reload!(order).status == :preparing
    end

    test "re-enabling does not replay a cancelled ready" do
      branch = kitchen_branch()
      cook = staff(["orders.cook"], branch)
      order = order(branch, status: :preparing)

      assert {:ok, _order} = Kitchen.mark_ready(cook, branch.id, order.id)
      assert :ok = Kitchen.undo_ready(cook, branch.id, order.id)

      set_kitchen(branch, false)
      set_kitchen(branch, true)

      assert Kitchen.pending_ready(branch.id) == %{}
      assert Repo.reload!(order).status == :preparing
    end
  end

  defp set_kitchen(branch, enabled) do
    admin = staff(["admin"], branch)

    assert {:ok, _branch} =
             Delivest.Identity.update_branch(admin, branch, %{}, %{
               "kitchen" => %{"enabled" => enabled}
             })
  end

  defp transitions(order) do
    OrderTransition
    |> where([t], t.order_id == ^order.id)
    |> order_by([t], asc: t.id)
    |> select([t], {t.from, t.to, t.source})
    |> Repo.all()
  end
end
