defmodule Delivest.BackgroundTest do
  use Delivest.DataCase, async: false
  use Oban.Testing, repo: Delivest.Repo

  import Ecto.Query
  alias Delivest.{Background, Features, Repo}
  alias Delivest.Background.{Dispatcher, Runner, Schedule}

  test "disabled installation has no work; due scheduling coalesces" do
    assert :ok = Background.reconcile()
    assert {:ok, 0} = Background.dispatch_due()
    refute_enqueued(worker: Runner)

    assert {:ok, _} = Features.configure("segments", :franchise, true, actor: "host")
    assert {:ok, 1} = Background.dispatch_due()
    assert {:ok, 0} = Background.dispatch_due()
    assert_enqueued(worker: Runner)
    assert Repo.one!(Schedule).running
  end

  test "reconcile restores only an enabled schedule after a database swap" do
    assert {:ok, _} = Features.configure("segments", :franchise, true, actor: "host")
    Repo.delete_all(Schedule)
    assert :ok = Background.reconcile()
    assert Repo.aggregate(Schedule, :count) == 1
    assert :ok = Background.reconcile()
    assert Repo.aggregate(Schedule, :count) == 1
    assert {:ok, _} = Features.configure("segments", :franchise, false, actor: "host")
    assert :ok = Background.reconcile()
    assert Repo.aggregate(Schedule, :count) == 0
  end

  test "critical backlog defers without consuming due schedule" do
    assert {:ok, _} = Features.configure("segments", :franchise, true, actor: "host")
    old = Application.get_env(:delivest, :background_pressure_limit)
    Application.put_env(:delivest, :background_pressure_limit, 0)

    on_exit(fn ->
      if old,
        do: Application.put_env(:delivest, :background_pressure_limit, old),
        else: Application.delete_env(:delivest, :background_pressure_limit)
    end)

    assert {:deferred, :critical_backlog} = Background.dispatch_due()
    refute_enqueued(worker: Runner)
    refute Repo.one!(Schedule).running
    assert Background.overdue_count() == 1
  end

  test "disable cancels pending work and old generation cannot publish" do
    assert {:ok, _} = Features.configure("segments", :franchise, true, actor: "host")
    assert {:ok, token} = Features.snapshot("segments", :franchise)
    assert {:ok, 1} = Background.dispatch_due()
    pending = Repo.one!(Schedule)
    stale_job = Repo.get!(Oban.Job, pending.current_job_id)
    assert {:ok, _} = Features.configure("segments", :franchise, false, actor: "host")
    assert {:cancel, :disabled} = Runner.perform(stale_job)
    assert Repo.aggregate(Schedule, :count) == 0
    assert {:ok, _} = Features.configure("segments", :franchise, true, actor: "host")
    context = %{feature: "segments", scope: :franchise, generation: token}
    refute Background.still_enabled?(context)
    assert {:error, :disabled} = Background.publish(context, fn -> flunk("stale result") end)
  end

  test "terminal job recovers and stale finish cannot mutate a newer schedule" do
    assert {:ok, _} = Features.configure("segments", :franchise, true, actor: "host")
    assert {:ok, 1} = Background.dispatch_due()
    first = Repo.one!(Schedule)
    assert is_integer(first.current_job_id)
    assert is_nil(first.last_error_at)

    Repo.update_all(from(j in Oban.Job, where: j.id == ^first.current_job_id),
      set: [state: "discarded"]
    )

    assert {:ok, 0} = Background.dispatch_due()
    recovered = Repo.one!(Schedule)
    refute recovered.running
    assert is_nil(recovered.current_job_id)
    assert recovered.last_error_at
    assert recovered.last_error == "background calculation terminated before completion"
    assert DateTime.compare(recovered.next_at, DateTime.utc_now()) == :gt

    assert {:ok, _} = Features.configure("segments", :franchise, false, actor: "host")
    assert {:ok, _} = Features.configure("segments", :franchise, true, actor: "host")
    replacement = Repo.one!(Schedule)
    Background.finish(first.kind, first.scope_key, first.current_job_id, :ok)
    assert Repo.reload!(replacement).next_at == replacement.next_at
    assert is_nil(Repo.reload!(replacement).last_success_at)
  end

  test "branch gate change invalidates franchise run ownership" do
    branch = Delivest.Factory.insert(:branch)
    assert {:ok, _} = Features.configure("segments", :franchise, true, actor: "host")
    assert {:ok, token} = Features.snapshot("segments", :franchise)
    assert {:ok, 1} = Background.dispatch_due()
    old = Repo.one!(Schedule)

    context = %{
      feature: "segments",
      scope: :franchise,
      generation: token,
      schedule_id: old.id,
      job_id: old.current_job_id
    }

    assert Background.still_enabled?(context)
    assert :ok = Background.checkpoint(context)
    old_limit = Application.get_env(:delivest, :background_pressure_limit)

    on_exit(fn ->
      if old_limit,
        do: Application.put_env(:delivest, :background_pressure_limit, old_limit),
        else: Application.delete_env(:delivest, :background_pressure_limit)
    end)

    Application.put_env(:delivest, :background_pressure_limit, 0)
    assert {:snooze, 300} = Background.checkpoint(context)

    if old_limit,
      do: Application.put_env(:delivest, :background_pressure_limit, old_limit),
      else: Application.delete_env(:delivest, :background_pressure_limit)

    assert {:ok, _} = Features.configure("segments", {:branch, branch.id}, true, actor: "host")
    refute Background.still_enabled?(context)
    assert {:error, :disabled} = Background.checkpoint(context)
    assert {:error, :disabled} = Background.publish(context, fn -> flunk("old run wrote") end)
    assert is_nil(Repo.reload!(old).current_job_id)
  end

  test "persisted runner context reaches handler and publishes success" do
    assert {:ok, _} = Features.configure("segments", :franchise, true, actor: "host")
    assert {:ok, 1} = Background.dispatch_due()
    schedule = Repo.one!(Schedule)
    job = Repo.get!(Oban.Job, schedule.current_job_id)
    assert job.args["schedule_id"] == schedule.id
    assert Runner.timeout(job) == :timer.minutes(15)
    assert Dispatcher.timeout(%Oban.Job{}) == :timer.seconds(30)
    [[previous_timeout]] = Repo.query!("SHOW statement_timeout").rows
    Repo.query!("SELECT set_config('statement_timeout', '2s', false)")
    assert :ok = Runner.perform(job)
    assert Repo.query!("SHOW statement_timeout").rows == [["2s"]]
    Repo.query!("SELECT set_config('statement_timeout', $1, false)", [previous_timeout])
    assert Repo.reload!(schedule).last_success_at
    refute Repo.reload!(schedule).running
  end

  test "unknown stored scope fails closed and is removed without a job" do
    assert {:ok, _} = Features.configure("segments", :franchise, true, actor: "host")
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    Repo.insert!(%Schedule{kind: "segments.refresh", scope_key: "unrecognized", next_at: now})
    assert {:ok, 1} = Background.dispatch_due()
    refute Repo.exists?(from s in Schedule, where: s.scope_key == "unrecognized")

    refute Repo.exists?(
             from j in Oban.Job,
               where: fragment("?->>'scope_key'", j.args) == "unrecognized"
           )
  end

  test "disable waits for a schedule lock and old job cannot finish a replacement" do
    unboxed(fn ->
      assert {:ok, _} = Features.configure("segments", :franchise, true, actor: "race")
    end)

    assert {:ok, 1} = unboxed(fn -> Background.dispatch_due() end)
    first = unboxed(fn -> Repo.one!(Schedule) end)
    parent = self()

    holder =
      Task.async(fn ->
        unboxed(fn ->
          Repo.transaction(fn ->
            Repo.one!(from s in Schedule, where: s.id == ^first.id, lock: "FOR UPDATE")
            send(parent, {:schedule_locked, self()})

            receive do
              :release_schedule ->
                Background.finish(first.kind, first.scope_key, first.current_job_id, :ok)
            after
              5_000 -> raise "schedule test barrier timed out"
            end
          end)
        end)
      end)

    assert_receive {:schedule_locked, holder_pid}

    changer =
      Task.async(fn ->
        unboxed(fn ->
          {:ok, _} = Features.configure("segments", :franchise, false, actor: "race")
          {:ok, _} = Features.configure("segments", :franchise, true, actor: "race")
          send(parent, :replacement_done)
        end)
      end)

    refute_receive :replacement_done, 100
    send(holder_pid, :release_schedule)
    assert {:ok, :ok} = Task.await(holder, 5_000)
    assert :replacement_done = Task.await(changer, 5_000)
    replacement = unboxed(fn -> Repo.one!(Schedule) end)
    assert replacement.id != first.id
    assert is_nil(replacement.last_success_at)
    unboxed(fn -> Background.finish(first.kind, first.scope_key, first.current_job_id, :ok) end)
    assert is_nil(unboxed(fn -> Repo.reload!(replacement).last_success_at end))
    unboxed(fn -> Features.configure("segments", :franchise, false, actor: "race") end)
  end

  defp unboxed(fun), do: Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fun)
end
