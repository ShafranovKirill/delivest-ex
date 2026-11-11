defmodule Delivest.Maintenance.DispatchWorkerTest do
  use Delivest.DataCase, async: false

  import Delivest.Factory

  alias Delivest.Maintenance.{DailyJob, DailyRun, DispatchWorker, Registry}

  setup do
    previous_tasks = Application.get_env(:delivest, Registry)
    previous_result = Application.get_env(:delivest, Delivest.MaintenanceTestWorker)

    on_exit(fn ->
      if previous_tasks,
        do: Application.put_env(:delivest, Registry, previous_tasks),
        else: Application.delete_env(:delivest, Registry)

      if previous_result,
        do: Application.put_env(:delivest, Delivest.MaintenanceTestWorker, previous_result),
        else: Application.delete_env(:delivest, Delivest.MaintenanceTestWorker)
    end)

    task = %{key: "test_daily", worker: Delivest.MaintenanceTestWorker, scope: :global, hour: 3}
    Application.put_env(:delivest, Registry, [task])
    %{task: task}
  end

  test "due boundary selects the most recent local day, including only one missed day" do
    date = ~D[2026-11-11]
    due = DispatchWorker.due_at(date, "Europe/Moscow", 3)

    assert DispatchWorker.latest_due_date(DateTime.add(due, -1), "Europe/Moscow", 3) ==
             Date.add(date, -1)

    assert DispatchWorker.latest_due_date(due, "Europe/Moscow", 3) == date

    assert DispatchWorker.latest_due_date(DateTime.add(due, 4 * 86_400), "Europe/Moscow", 3) ==
             Date.add(date, 4)

    assert DispatchWorker.latest_due_date(~U[2026-11-11 16:00:00Z], "Asia/Kamchatka", 3) ==
             ~D[2026-11-12]

    assert DispatchWorker.latest_due_date(~U[2026-11-11 16:00:00Z], "Europe/Moscow", 3) == date
  end

  test "DST gap uses next valid instant and fold uses the first instant" do
    assert DispatchWorker.due_at(~D[2026-03-29], "Europe/Berlin", 2) == ~U[2026-03-29 01:00:00Z]
    assert DispatchWorker.due_at(~D[2026-10-25], "Europe/Berlin", 2) == ~U[2026-10-25 00:00:00Z]
  end

  test "branch scope reads fresh timezone directly from BranchInfo", %{task: task} do
    branch = insert(:branch)

    info =
      Repo.insert!(%Delivest.Identity.Branch.BranchInfo{
        branch_id: branch.id,
        timezone: "Europe/Moscow"
      })

    branch_task = %{task | scope: :branch, hour: 6}

    assert [{^branch_task, "branch", branch_id, "Europe/Moscow"}] =
             Registry.scopes(branch_task) |> Enum.filter(&(elem(&1, 2) == branch.id))

    assert branch_id == branch.id
    Application.put_env(:delivest, Registry, [branch_task])
    now = ~U[2026-11-11 19:00:00Z]
    assert :ok = DispatchWorker.dispatch(now)
    first = Repo.one!(DailyRun)
    assert first.local_date == ~D[2026-11-11]

    Repo.get!(Oban.Job, first.job_id)
    |> Ecto.Changeset.change(state: "completed")
    |> Repo.update!()

    info |> Ecto.Changeset.change(timezone: "Asia/Kamchatka") |> Repo.update!()

    assert [{^branch_task, "branch", ^branch_id, "Asia/Kamchatka"}] =
             Registry.scopes(branch_task) |> Enum.filter(&(elem(&1, 2) == branch.id))

    assert :ok = DispatchWorker.dispatch(now)

    assert Repo.get_by!(DailyRun, task_key: task.key, local_date: ~D[2026-11-12]).scope_id ==
             branch.id
  end

  test "dispatch inserts one durable marker and job, then defers the next date while active", %{
    task: task
  } do
    first = ~D[2026-11-10]
    second = ~D[2026-11-11]
    assert {:ok, :scheduled} = DispatchWorker.schedule(task, "global", "global", first)
    assert {:ok, :already} = DispatchWorker.schedule(task, "global", "global", first)
    assert {:ok, :busy} = DispatchWorker.schedule(task, "global", "global", second)
    assert Repo.aggregate(DailyRun, :count) == 1

    run = Repo.one!(DailyRun)
    job = Repo.get!(Oban.Job, run.job_id)
    assert job.args["local_date"] == "2026-11-10"
    assert job.worker == Oban.Worker.to_string(DailyJob)

    job |> Ecto.Changeset.change(state: "completed") |> Repo.update!()
    assert {:ok, :scheduled} = DispatchWorker.schedule(task, "global", "global", second)
    assert Repo.aggregate(DailyRun, :count) == 2
  end

  test "dispatch catches up only latest due date after several missed days" do
    now = ~U[2026-11-11 12:00:00Z]
    assert :ok = DispatchWorker.dispatch(now)
    assert [run] = Repo.all(DailyRun)
    assert run.local_date == ~D[2026-11-11]
  end

  test "orphaned terminal and pruned jobs become observable failures without blocking the next day",
       %{task: task} do
    assert {:ok, :scheduled} = DispatchWorker.schedule(task, "global", "global", ~D[2026-11-10])
    run = Repo.one!(DailyRun)
    job = Repo.get!(Oban.Job, run.job_id)
    run |> Ecto.Changeset.change(status: "running") |> Repo.update!()
    job |> Ecto.Changeset.change(state: "discarded") |> Repo.update!()

    assert {:ok, :scheduled} = DispatchWorker.schedule(task, "global", "global", ~D[2026-11-11])
    failed = Repo.get!(DailyRun, run.id)
    assert failed.status == "failed"
    assert failed.finished_at
    assert failed.last_error =~ "discarded"

    second = Repo.get_by!(DailyRun, task_key: task.key, local_date: ~D[2026-11-11])
    second |> Ecto.Changeset.change(status: "running") |> Repo.update!()
    Repo.get!(Oban.Job, second.job_id) |> Repo.delete!()
    assert {:ok, :scheduled} = DispatchWorker.schedule(task, "global", "global", ~D[2026-11-12])
    assert Repo.get!(DailyRun, second.id).last_error =~ "missing"
  end

  test "registered timeout stays below the configured Lifeline rescue", %{task: task} do
    max_timeout = Registry.max_timeout_ms()
    assert max_timeout == :timer.minutes(90)
    assert max_timeout < :timer.hours(2)
    assert DailyJob.timeout(%Oban.Job{args: %{"task_key" => task.key}}) == max_timeout
    invalid = Map.put(task, :timeout_ms, max_timeout + 1)
    assert Registry.validate(invalid) == {:error, :invalid_timeout}

    assert {:error, :invalid_timeout} =
             DispatchWorker.schedule(invalid, "global", "global", ~D[2026-11-11])

    assert Repo.aggregate(DailyRun, :count) == 0
  end

  test "overlapping dispatch calls create one run under the SQL sandbox", %{task: task} do
    supervisor = start_supervised!(Task.Supervisor)

    results =
      1..2
      |> Enum.map(fn _ ->
        Task.Supervisor.async_nolink(supervisor, fn ->
          DispatchWorker.schedule(task, "global", "global", ~D[2026-11-11])
        end)
      end)
      |> Enum.map(&Task.await(&1, 10_000))

    assert Enum.sort(results) == Enum.sort([{:ok, :scheduled}, {:ok, :already}])
    assert Repo.aggregate(DailyRun, :count) == 1

    assert Repo.aggregate(
             from(j in Oban.Job, where: j.worker == ^Oban.Worker.to_string(DailyJob)),
             :count
           ) == 1
  end

  test "only four heavy automatic cron entries were replaced" do
    cron = :delivest |> Application.fetch_env!(Oban) |> Keyword.fetch!(:crontab)
    queues = :delivest |> Application.fetch_env!(Oban) |> Keyword.fetch!(:queues)
    assert Keyword.fetch!(queues, :maintenance) == 1
    assert Keyword.fetch!(queues, :maintenance_schedule) == 1
    assert Ecto.Changeset.get_field(DispatchWorker.new(%{}), :queue) == "maintenance_schedule"
    assert Ecto.Changeset.get_field(DailyJob.new(%{}), :queue) == "maintenance"
    assert {"* * * * *", DispatchWorker} in cron
    assert {"5 * * * *", Delivest.Oms.Workers.StaleOrderWorker} in cron
    assert {"0 10 * * *", Delivest.Loyalty.ExpiryNoticeWorker} in cron

    assert {"17 4 * * *", Delivest.Integrations.Poller.Worker, args: %{poller: "crm_catalog"}} in cron

    refute Enum.any?(cron, fn
             {_, worker} ->
               worker in [
                 Delivest.Oms.Workers.CartCleanupWorker,
                 Delivest.Loyalty.ExpireWorker,
                 Delivest.Logs.PruneWorker,
                 Delivest.Media.Workers.ThumbnailBackfillWorker
               ]

             _ ->
               false
           end)
  end

  test "completed run replay skips the delegate and preserves timestamps", %{task: task} do
    assert {:ok, :scheduled} = DispatchWorker.schedule(task, "global", "global", ~D[2026-11-11])
    run = Repo.one!(DailyRun)
    job = Repo.get!(Oban.Job, run.job_id)
    Application.put_env(:delivest, Delivest.MaintenanceTestWorker, {:notify, self()})

    assert {:error, :unknown_daily_run} =
             DailyJob.perform(%{job | args: Map.put(job.args, "scope_id", "foreign")})

    refute_receive :maintenance_called

    assert :ok = DailyJob.perform(%{job | attempt: 1})
    assert_receive :maintenance_called
    finished = Repo.get!(DailyRun, run.id)
    assert finished.status == "completed"

    assert :ok = DailyJob.perform(%{job | attempt: 2})
    refute_receive :maintenance_called
    replayed = Repo.get!(DailyRun, run.id)
    assert replayed.started_at == finished.started_at
    assert replayed.finished_at == finished.finished_at
    assert replayed.updated_at == finished.updated_at
  end

  test "wrapper records snooze, retry, terminal failure, and completion", %{task: task} do
    assert {:ok, :scheduled} = DispatchWorker.schedule(task, "global", "global", ~D[2026-11-11])
    run = Repo.one!(DailyRun)
    job = Repo.get!(Oban.Job, run.job_id)

    Application.put_env(:delivest, Delivest.MaintenanceTestWorker, {:snooze, 1})
    assert {:snooze, 1} = DailyJob.perform(%{job | attempt: 1})
    assert Repo.get!(DailyRun, run.id).status == "snoozed"

    Application.put_env(:delivest, Delivest.MaintenanceTestWorker, {:error, :offline})
    assert {:error, :offline} = DailyJob.perform(%{job | attempt: 2})
    assert Repo.get!(DailyRun, run.id).status == "retrying"
    assert {:error, :offline} = DailyJob.perform(%{job | attempt: job.max_attempts})
    assert Repo.get!(DailyRun, run.id).status == "failed"
    assert Repo.get!(DailyRun, run.id).finished_at

    Application.put_env(:delivest, Delivest.MaintenanceTestWorker, :ok)
    assert :ok = DailyJob.perform(%{job | attempt: 1})
    assert Repo.get!(DailyRun, run.id).status == "completed"
  end
end
