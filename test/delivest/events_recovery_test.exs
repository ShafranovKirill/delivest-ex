defmodule Delivest.EventsRecoveryTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Delivest.Events
  alias Delivest.Events.{DeliverWorker, Delivery, Event, RecoveryProbe}
  alias Delivest.Oms.Order
  alias Delivest.Repo

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    Application.put_env(:delivest, :event_subscribers, [RecoveryProbe])
    aggregate_id = Ecto.UUID.generate()

    on_exit(fn ->
      Application.delete_env(:delivest, RecoveryProbe)
      Application.delete_env(:delivest, :event_subscribers)

      Repo.delete_all(
        from(j in Oban.Job,
          where: j.worker == ^Oban.Worker.to_string(DeliverWorker),
          where: fragment("?->>'subscriber' = 'recovery_probe'", j.args)
        )
      )

      Repo.delete_all(from(e in Event, where: e.aggregate_id == ^aggregate_id))
      Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
    end)

    {:ok, aggregate_id: aggregate_id}
  end

  test "kill before local commit rolls back work and retry commits once", %{aggregate_id: id} do
    {:ok, event} = Events.record("order.status_changed", %Order{id: id}, %{}, %{})
    job = job(event)
    Application.put_env(:delivest, RecoveryProbe, %{owner: self(), barrier: :before_commit})

    {pid, ref} = spawn_monitor(fn -> DeliverWorker.perform(job) end)
    assert_receive {:probe_written, ^pid, event_id, [worker_backend]}, 5_000
    assert event_id == event.id

    [[test_backend]] = Ecto.Adapters.SQL.query!(Repo, "SELECT pg_backend_pid()", []).rows
    refute test_backend == worker_backend

    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 5_000

    assert side_effects(id) == 0

    assert Repo.get_by!(Delivery, event_id: event.id, subscriber: "recovery_probe").status ==
             "pending"

    Application.delete_env(:delivest, RecoveryProbe)
    assert :ok = DeliverWorker.perform(job)
    assert side_effects(id) == 1
  end

  test "kill after commit but before job completion cannot repeat local work", %{aggregate_id: id} do
    {:ok, event} = Events.record("order.status_changed", %Order{id: id}, %{}, %{})
    job = job(event)
    owner = self()

    {pid, ref} =
      spawn_monitor(fn ->
        result = DeliverWorker.perform(job)
        send(owner, {:performed, self(), result})

        receive do
          :finish -> :ok
        end
      end)

    assert_receive {:performed, ^pid, :ok}, 5_000
    assert side_effects(id) == 1

    assert Repo.get_by!(Delivery, event_id: event.id, subscriber: "recovery_probe").status ==
             "delivered"

    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 5_000
    assert :ok = DeliverWorker.perform(job)
    assert side_effects(id) == 1
  end

  defp job(event) do
    Repo.one!(
      from(j in Oban.Job,
        where: j.worker == ^Oban.Worker.to_string(DeliverWorker),
        where: fragment("?->>'event_id' = ?", j.args, ^event.id),
        where: fragment("?->>'subscriber' = 'recovery_probe'", j.args)
      )
    )
  end

  defp side_effects(id),
    do:
      Repo.aggregate(
        from(e in Event, where: e.aggregate_id == ^id and e.type == "probe.side_effect"),
        :count
      )
end
