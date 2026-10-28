defmodule Delivest.Oms.KitchenTest do
  use Delivest.DataCase, async: true
  use Oban.Testing, repo: Delivest.Repo

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.LocalTime
  alias Delivest.Oms.{Kitchen, Order, Orders, OrderTransition}
  alias Delivest.Oms.Kitchen.ReadyWorker

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
      |> LocalTime.utc_to_naive()
      |> NaiveDateTime.truncate(:second)

  defp operator(branch), do: {:staff, staff(["orders.update"], branch)}

  describe "sending to the kitchen" do
    test "an order for now goes to the kitchen when it is confirmed" do
      branch = kitchen_branch()
      order = order(branch, [])

      assert {:ok, %Order{status: :preparing}} =
               Orders.advance_order(order, :accepted, operator(branch))

      assert [{:created, :accepted, :staff}, {:accepted, :preparing, :system}] =
               transitions(order)
    end

    test "an order for later waits until the lead time" do
      branch = kitchen_branch()
      later = order(branch, cook_by: in_minutes(120))
      soon = order(branch, cook_by: in_minutes(80))

      assert {:ok, %Order{status: :accepted}} =
               Orders.advance_order(later, :accepted, operator(branch))

      assert {:ok, %Order{status: :preparing}} =
               Orders.advance_order(soon, :accepted, operator(branch))

      Kitchen.dispatch_due(DateTime.add(DateTime.utc_now(), 29, :minute))
      assert Repo.reload!(later).status == :accepted

      Kitchen.dispatch_due(DateTime.add(DateTime.utc_now(), 31, :minute))
      assert Repo.reload!(later).status == :preparing
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

  defp transitions(order) do
    OrderTransition
    |> where([t], t.order_id == ^order.id)
    |> order_by([t], asc: t.id)
    |> select([t], {t.from, t.to, t.source})
    |> Repo.all()
  end
end
