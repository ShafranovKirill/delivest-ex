defmodule Delivest.EventsConcurrencyTest do
  use Delivest.DataCase, async: false
  use Oban.Testing, repo: Delivest.Repo

  alias Delivest.Events
  alias Delivest.Events.{DeliverWorker, Delivery, Event, Recovery}
  alias Delivest.Oms.Order

  defmodule Probe do
    @behaviour Delivest.Events.Subscriber
    alias Delivest.Events.Event
    alias Delivest.Repo

    def key, do: :probe
    def events, do: ["order.status_changed"]

    def handle(%Event{} = event) do
      event
      |> Ecto.Changeset.change(payload: Map.put(event.payload, "handled", true))
      |> Repo.update!()

      case Application.get_env(:delivest, :event_probe_parent) do
        nil ->
          :ok

        parent ->
          send(parent, {:inside_delivery, self()})

          receive do
            :continue -> :ok
          end
      end
    end
  end

  test "process death before commit rolls back the effect and ack; a new connection retries" do
    Application.put_env(:delivest, :event_subscribers, [Probe])
    Application.put_env(:delivest, :event_probe_parent, self())

    on_exit(fn ->
      Application.delete_env(:delivest, :event_subscribers)
      Application.delete_env(:delivest, :event_probe_parent)
    end)

    aggregate = %Order{id: Ecto.UUID.generate()}

    {:ok, event} =
      Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
        Events.record("order.status_changed", aggregate, %{}, %{kind: :system})
      end)

    admin =
      Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
        Delivest.Factory.insert(:staff,
          role: Delivest.Factory.build(:role, permissions: ["admin"])
        )
      end)

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
        Repo.delete!(admin)
        Repo.delete!(admin.role)

        Repo.delete_all(
          from j in Oban.Job, where: fragment("?->>'event_id'", j.args) == ^event.id
        )

        Repo.delete_all(from d in Delivery, where: d.event_id == ^event.id)
        Repo.delete_all(from e in Event, where: e.id == ^event.id)

        Repo.query!(
          "DELETE FROM event_sequences WHERE aggregate_type = $1 AND aggregate_id = $2",
          ["order", Ecto.UUID.dump!(aggregate.id)]
        )
      end)
    end)

    {child, ref} =
      spawn_monitor(fn ->
        Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
          perform_job(DeliverWorker, %{event_id: event.id, subscriber: "probe"})
        end)
      end)

    on_exit(fn -> Process.exit(child, :kill) end)

    assert_receive {:inside_delivery, ^child}, 5_000

    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      lock_key = "order:#{aggregate.id}:probe"

      assert %{rows: [[false]]} =
               Repo.query!("SELECT pg_try_advisory_xact_lock(hashtextextended($1, 0))", [lock_key])
    end)

    assert {:error, :busy_delivery} =
             Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
               Recovery.resolve(event.id, "probe", admin.id, "handler is active")
             end)

    Process.exit(child, :kill)
    assert_receive {:DOWN, ^ref, :process, ^child, :killed}, 5_000

    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      assert %Event{payload: payload} = Repo.get!(Event, event.id)
      refute Map.has_key?(payload, "handled")

      assert %Delivery{status: "pending"} =
               Repo.get_by!(Delivery, event_id: event.id, subscriber: "probe")
    end)

    Application.delete_env(:delivest, :event_probe_parent)

    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      assert :ok = perform_job(DeliverWorker, %{event_id: event.id, subscriber: "probe"})
      assert %Event{payload: %{"handled" => true}} = Repo.get!(Event, event.id)

      assert %Delivery{status: "delivered"} =
               Repo.get_by!(Delivery, event_id: event.id, subscriber: "probe")
    end)
  end

  test "two independent writers receive commit-ordered aggregate sequences" do
    Application.put_env(:delivest, :event_subscribers, [])
    on_exit(fn -> Application.delete_env(:delivest, :event_subscribers) end)
    aggregate = %Order{id: Ecto.UUID.generate()}
    parent = self()

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
        Repo.delete_all(from e in Event, where: e.aggregate_id == ^aggregate.id)

        Repo.query!(
          "DELETE FROM event_sequences WHERE aggregate_type = $1 AND aggregate_id = $2",
          ["order", Ecto.UUID.dump!(aggregate.id)]
        )
      end)
    end)

    {first, first_ref} =
      spawn_monitor(fn ->
        Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
          Repo.transaction(fn ->
            {:ok, event} = Events.record("order.status_changed", aggregate, %{}, %{kind: :system})
            send(parent, {:first_inserted, event.id, event.sequence})

            receive do
              :commit -> :ok
            end
          end)
        end)
      end)

    on_exit(fn -> Process.exit(first, :kill) end)

    assert_receive {:first_inserted, first_id, 1}, 5_000

    {second, second_ref} =
      spawn_monitor(fn ->
        Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
          send(parent, :second_started)
          result = Events.record("order.status_changed", aggregate, %{}, %{kind: :system})
          send(parent, {:second_finished, result})
        end)
      end)

    on_exit(fn -> Process.exit(second, :kill) end)

    assert_receive :second_started, 5_000
    refute_receive {:second_finished, _}, 100
    send(first, :commit)
    assert_receive {:DOWN, ^first_ref, :process, ^first, :normal}, 5_000
    assert_receive {:second_finished, {:ok, %Event{sequence: 2}}}, 5_000
    assert_receive {:DOWN, ^second_ref, :process, ^second, :normal}, 5_000

    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      assert [^first_id, _second_id] =
               Repo.all(
                 from e in Event,
                   where: e.aggregate_id == ^aggregate.id,
                   order_by: e.sequence,
                   select: e.id
               )
    end)
  end
end
