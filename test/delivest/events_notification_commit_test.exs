defmodule Delivest.EventsNotificationCommitTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Delivest.Factory

  alias Delivest.Events.{DeliverWorker, Delivery, Event}
  alias Delivest.Oms.{Cart, Order}
  alias Delivest.Oms.Orders.Notifier
  alias Delivest.Repo

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    branch = insert(:branch)
    cart = Repo.insert!(%Cart{branch_id: branch.id})

    order =
      Repo.insert!(%Order{
        branch_id: branch.id,
        cart_id: cart.id,
        number: "notification-#{System.unique_integer([:positive])}",
        business_date: Date.utc_today(),
        daily_number: System.unique_integer([:positive]),
        status: :accepted
      })

    Notifier.subscribe(branch.id)

    on_exit(fn ->
      Repo.delete!(order)
      Repo.delete!(cart)
      Repo.delete!(branch)
      Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
    end)

    {:ok, order: order}
  end

  test "notification is sent after commit with state visible on another connection", %{
    order: order
  } do
    supervisor = start_supervised!({Task.Supervisor, []})
    parent = self()

    task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        Notifier.with_commit_notifications(fn ->
          Repo.transaction(fn ->
            preparing = order |> Ecto.Changeset.change(status: :preparing) |> Repo.update!()
            assert {:ok, returned} = Notifier.publish({:ok, preparing}, [:order, :updated])
            assert returned.status == :preparing
            assert returned.items == []
            send(parent, {:before_commit, self()})
            receive do: (:commit -> :ok)
          end)
        end)
      end)

    assert_receive {:before_commit, worker}
    assert Repo.get!(Order, order.id).status == :accepted
    refute_receive {Delivest.Oms.Orders, [:order, :updated], _}, 50
    send(worker, :commit)
    assert {:ok, :ok} = Task.await(task)
    assert_receive {Delivest.Oms.Orders, [:order, :updated], published}
    assert published.status == :preparing
    assert Repo.get!(Order, order.id).status == :preparing
  end

  test "rolled-back transaction discards notification", %{order: order} do
    assert {:error, :cancelled} =
             Notifier.with_commit_notifications(fn ->
               Repo.transaction(fn ->
                 preparing = order |> Ecto.Changeset.change(status: :preparing) |> Repo.update!()
                 Notifier.publish({:ok, preparing}, [:order, :updated])
                 Repo.rollback(:cancelled)
               end)
             end)

    assert Repo.get!(Order, order.id).status == :accepted
    refute_receive {Delivest.Oms.Orders, [:order, :updated], _}, 50
  end

  test "stale input publishes the current row and returns the input", %{order: order} do
    preparing = order |> Ecto.Changeset.change(status: :preparing) |> Repo.update!()
    assert {:ok, returned} = Notifier.publish({:ok, order}, [:order, :updated])
    assert returned.id == order.id
    assert returned.status == :accepted
    assert returned.items == []
    assert returned.deliveries == []
    assert_receive {Delivest.Oms.Orders, [:order, :updated], published}
    assert published.id == preparing.id
    assert published.status == :preparing
  end

  test "already delivered replay invalidates current order without rerunning subscriber", %{
    order: order
  } do
    event =
      Repo.insert!(%Event{
        type: "order.updated",
        aggregate_type: "order",
        aggregate_id: order.id,
        branch_id: order.branch_id,
        actor: %{"kind" => "staff"},
        payload: %{
          "changes" => %{
            "items" => %{"from" => [%{"title" => "Soup", "quantity" => 1}], "to" => []}
          }
        }
      })

    delivery =
      Repo.insert!(%Delivery{event_id: event.id, subscriber: "push", status: "delivered"})

    on_exit(fn ->
      Repo.delete!(delivery)
      Repo.delete!(event)
    end)

    preparing = order |> Ecto.Changeset.change(status: :preparing) |> Repo.update!()
    job = %Oban.Job{args: %{"event_id" => event.id, "subscriber" => "push"}}

    assert :ok = DeliverWorker.perform(job)
    assert_receive {Delivest.Oms.Orders, [:order, :updated], published}
    assert published.id == preparing.id
    assert published.status == :preparing

    refute Repo.exists?(
             from(j in Oban.Job,
               where: j.worker == ^Oban.Worker.to_string(Delivest.Push.NoteWorker),
               where: fragment("?->>'event_id' = ?", j.args, ^event.id)
             )
           )
  end
end
