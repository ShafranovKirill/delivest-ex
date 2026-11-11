defmodule Delivest.BackgroundTest do
  use Delivest.DataCase, async: false
  use Oban.Testing, repo: Delivest.Repo

  import Ecto.Query
  alias Delivest.{Background, Features, Repo}
  alias Delivest.Background.{DailySchedule, Dispatcher, Registry, Runner, Schedule}

  test "only five bounded daily calculations use local 03:00" do
    daily =
      Registry.all()
      |> Enum.filter(fn {_kind, task} -> Map.get(task, :schedule) == :daily_03 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    assert daily ==
             Enum.sort(
               ~w(analytics.extended marketing.preview marketing.report marketing.evaluate segments.refresh)
             )

    for kind <- ~w(analytics.funnel analytics.links notifications.dispatch) do
      {:ok, task} = Registry.fetch(kind)
      refute Map.has_key?(task, :schedule)
    end
  end

  test "legacy rolling schedule catches up once and manual rerun remains immediate" do
    assert {:ok, _} = Features.configure("segments", :franchise, true, actor: "host")
    schedule = Repo.get_by!(Schedule, kind: "segments.refresh", scope_key: "franchise")
    past = DateTime.add(DateTime.utc_now(), -86_400, :second)
    Repo.update!(Ecto.Changeset.change(schedule, daily_date: nil, next_at: past))

    assert {:ok, 1} = Background.dispatch_due()
    running = Repo.reload!(schedule)

    assert running.daily_date ==
             DailySchedule.latest_due_date(DateTime.utc_now(), DailySchedule.zone("franchise"))

    assert :ok = Background.finish(running.kind, running.scope_key, running.current_job_id, :ok)
    completed = Repo.reload!(schedule)
    assert DateTime.compare(completed.next_at, DateTime.utc_now()) == :gt
    assert {:ok, 0} = Background.dispatch_due()

    assert {:ok, :queued} = Background.run_now("segments.refresh", :franchise)
    assert Repo.reload!(schedule).manual_requested
    assert {:ok, 1} = Background.dispatch_due()
    refute Repo.reload!(schedule).manual_requested
  end

  test "daily branch schedule recomputes UTC against fresh timezone" do
    branch = Delivest.Factory.insert(:branch)

    Repo.insert!(%Delivest.Identity.Branch.BranchInfo{
      branch_id: branch.id,
      timezone: "Europe/Moscow"
    })

    assert {:ok, _} = Features.configure("analytics_extended", :franchise, true, actor: "host")

    assert {:ok, _} =
             Features.configure("analytics_extended", {:branch, branch.id}, true, actor: "host")

    schedule =
      Repo.get_by!(Schedule, kind: "analytics.extended", scope_key: "branch:#{branch.id}")

    date = Date.add(Date.utc_today(), 10)

    Repo.update!(
      Ecto.Changeset.change(schedule,
        daily_date: date,
        next_at: DailySchedule.due_at(date, "Europe/Moscow")
      )
    )

    Repo.update_all(
      from(i in Delivest.Identity.Branch.BranchInfo,
        where: i.branch_id == ^branch.id
      ),
      set: [timezone: "America/New_York"]
    )

    assert {:ok, 0} = Background.dispatch_due()

    {expected_date, expected_at} =
      DailySchedule.next_future(DateTime.utc_now(), "America/New_York")

    assert Repo.reload!(schedule).daily_date == expected_date
    assert Repo.reload!(schedule).next_at == expected_at
  end

  test "notification dispatch keeps its rolling sixty-second interval" do
    assert {:ok, _} = Features.configure("notifications", :franchise, true, actor: "host")
    schedule = Repo.get_by!(Schedule, kind: "notifications.dispatch", scope_key: "franchise")
    assert is_nil(schedule.daily_date)
    assert DateTime.compare(schedule.next_at, DateTime.utc_now()) != :gt
    assert {:ok, 1} = Background.dispatch_due()

    running = Repo.reload!(schedule)
    assert :ok = Background.finish(running.kind, running.scope_key, running.current_job_id, :ok)
    finished = Repo.reload!(schedule)
    assert is_nil(finished.daily_date)
    assert DateTime.diff(finished.next_at, finished.last_success_at, :second) == 60
  end

  test "daily enable waits for local 03:00 and manual due scheduling coalesces" do
    assert :ok = Background.reconcile()
    assert {:ok, 0} = Background.dispatch_due()
    refute_enqueued(worker: Runner)

    assert {:ok, _} = Features.configure("segments", :franchise, true, actor: "host")
    assert {:ok, 0} = Background.dispatch_due()
    assert DateTime.compare(Repo.one!(Schedule).next_at, DateTime.utc_now()) == :gt
    assert {:ok, :queued} = Background.run_now("segments.refresh", :franchise)
    assert {:ok, 1} = Background.dispatch_due()
    assert {:ok, 0} = Background.dispatch_due()
    assert_enqueued(worker: Runner)
    assert Repo.one!(Schedule).running
  end

  test "interactive wakeups coalesce on the shared dispatcher" do
    assert {:ok, first} = Background.kick()
    assert {:ok, second} = Background.kick()
    assert first.id == second.id
    assert first.queue == "maintenance_schedule"

    assert Repo.get!(Oban.Job, first.id).state in ["available", "scheduled"]
  end

  test "manual idle nudges coalesce into one runner and status reads create no work" do
    assert {:error, :disabled} = Background.run_now("segments.refresh", :franchise)

    assert {:error, :invalid_schedule} =
             Background.run_now("notifications.dispatch", :franchise)

    assert {:ok, _} = Features.configure("segments", :franchise, true, actor: "host")
    schedule = Repo.get_by!(Schedule, kind: "segments.refresh", scope_key: "franchise")
    future = DateTime.add(DateTime.utc_now(), 86_400, :second)
    Repo.update!(Ecto.Changeset.change(schedule, next_at: future))

    assert {:ok, :queued} = Background.run_now("segments.refresh", :franchise)
    assert {:ok, :queued} = Background.run_now("segments.refresh", :franchise)
    assert {:ok, 1} = Background.dispatch_due()
    current = Repo.reload!(schedule)
    assert current.running
    assert is_integer(current.current_job_id)

    jobs_before = Repo.aggregate(Oban.Job, :count)

    assert {:ok, %{state: :queued}} =
             Background.calculation_status("segments.refresh", :franchise)

    assert Repo.aggregate(Oban.Job, :count) == jobs_before
    assert Repo.reload!(schedule).current_job_id == current.current_job_id

    assert Repo.aggregate(
             from(j in Oban.Job,
               where:
                 j.worker == "Delivest.Background.Runner" and
                   fragment("?->>'schedule_id'", j.args) == ^Integer.to_string(schedule.id)
             ),
             :count
           ) == 1
  end

  test "new work during an executing owner requests one immediate rerun" do
    assert {:ok, _} = Features.configure("segments", :franchise, true, actor: "host")
    assert {:ok, :queued} = Background.run_now("segments.refresh", :franchise)
    assert {:ok, 1} = Background.dispatch_due()
    first = Repo.get_by!(Schedule, kind: "segments.refresh", scope_key: "franchise")

    Repo.update_all(from(j in Oban.Job, where: j.id == ^first.current_job_id),
      set: [state: "executing"]
    )

    assert {:ok, :running} = Background.run_now("segments.refresh", :franchise)
    refute Repo.reload!(first).rerun_requested
    assert {:ok, :running} = Background.run_now("segments.refresh", :franchise, new_work: true)
    assert {:ok, :running} = Background.run_now("segments.refresh", :franchise, new_work: true)
    assert Repo.reload!(first).current_job_id == first.current_job_id
    assert Repo.reload!(first).rerun_requested

    assert :ok = Background.finish(first.kind, first.scope_key, first.current_job_id, :ok)
    finished = Repo.reload!(first)
    refute finished.running
    refute finished.rerun_requested
    assert DateTime.compare(finished.next_at, DateTime.utc_now()) != :gt
    assert {:ok, 1} = Background.dispatch_due()
    assert Repo.reload!(first).current_job_id != first.current_job_id
  end

  test "scheduled owner is expedited in place and a terminal owner is replaced" do
    assert {:ok, _} = Features.configure("segments", :franchise, true, actor: "host")
    assert {:ok, :queued} = Background.run_now("segments.refresh", :franchise)
    assert {:ok, 1} = Background.dispatch_due()
    first = Repo.get_by!(Schedule, kind: "segments.refresh", scope_key: "franchise")
    future = DateTime.add(DateTime.utc_now(), 86_400, :second)

    Repo.update_all(from(j in Oban.Job, where: j.id == ^first.current_job_id),
      set: [state: "scheduled", scheduled_at: future]
    )

    assert {:ok, :queued} = Background.run_now("segments.refresh", :franchise)
    assert Repo.reload!(first).current_job_id == first.current_job_id
    job = Repo.get!(Oban.Job, first.current_job_id)
    assert job.state == "available"
    assert DateTime.compare(job.scheduled_at, DateTime.utc_now()) != :gt
    assert {:ok, 0} = Background.dispatch_due()

    Repo.update_all(from(j in Oban.Job, where: j.id == ^first.current_job_id),
      set: [state: "retryable", scheduled_at: future]
    )

    assert {:ok, :queued} = Background.run_now("segments.refresh", :franchise)
    assert Repo.reload!(first).current_job_id == first.current_job_id
    assert Repo.get!(Oban.Job, first.current_job_id).state == "available"

    Repo.update_all(from(j in Oban.Job, where: j.id == ^first.current_job_id),
      set: [state: "discarded"]
    )

    assert {:ok, :queued} = Background.run_now("segments.refresh", :franchise)
    refute Repo.reload!(first).running
    assert {:ok, 1} = Background.dispatch_due()
    assert Repo.reload!(first).current_job_id != first.current_job_id
  end

  test "terminal recovery honors a durable rerun request" do
    assert {:ok, _} = Features.configure("segments", :franchise, true, actor: "host")
    assert {:ok, :queued} = Background.run_now("segments.refresh", :franchise)
    assert {:ok, 1} = Background.dispatch_due()
    first = Repo.get_by!(Schedule, kind: "segments.refresh", scope_key: "franchise")

    Repo.update!(Ecto.Changeset.change(first, rerun_requested: true))

    Repo.update_all(from(j in Oban.Job, where: j.id == ^first.current_job_id),
      set: [state: "discarded"]
    )

    assert {:ok, 1} = Background.dispatch_due()
    recovered = Repo.reload!(first)
    assert recovered.running
    refute recovered.rerun_requested
    assert recovered.current_job_id != first.current_job_id
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
    assert {:ok, :queued} = Background.run_now("segments.refresh", :franchise)
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
    assert {:ok, :queued} = Background.run_now("segments.refresh", :franchise)
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
    assert {:ok, :queued} = Background.run_now("segments.refresh", :franchise)
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
    assert {:ok, :queued} = Background.run_now("segments.refresh", :franchise)
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
    assert {:ok, :queued} = Background.run_now("segments.refresh", :franchise)
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
    assert {:ok, :queued} = Background.run_now("segments.refresh", :franchise)
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
      assert {:ok, :queued} = Background.run_now("segments.refresh", :franchise)
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
