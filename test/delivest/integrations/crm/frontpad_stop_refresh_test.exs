defmodule Delivest.Integrations.Crm.FrontpadStopRefreshTest do
  use Delivest.DataCase, async: false
  use Oban.Testing, repo: Delivest.Repo

  import Delivest.Factory

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Crm
  alias Delivest.Integrations.Crm.{BranchSettings, FrontpadStopRefresh, StopPoller}
  alias Delivest.Integrations.Crm.FrontpadStopRefresh.{RefreshJob, State}
  alias Delivest.Integrations.Frontpad
  alias Delivest.Integrations.Iiko
  alias Delivest.Maintenance.{DailyJob, DailyRun, DispatchWorker, Registry}
  alias Delivest.Net.Stops

  defp branch(enabled? \\ true, timezone \\ "Europe/Moscow") do
    branch = insert(:branch, is_active: true)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      timezone: timezone,
      crm: %BranchSettings{
        enabled: true,
        provider: :frontpad,
        frontpad: %Frontpad.Settings{api_key: "key", sync_stops: enabled?}
      }
    })

    branch
  end

  defp refresh_job(branch_id) do
    Repo.one!(
      from(j in Oban.Job,
        where:
          j.worker == ^Oban.Worker.to_string(RefreshJob) and
            fragment("?->>'branch_id' = ?", j.args, ^branch_id)
      )
    )
  end

  test "request queues without HTTP, coalesces an old retry and throttles a completed run" do
    branch = branch()
    test_pid = self()

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      send(test_pid, :provider_called)
      Req.Test.json(conn, %{"result" => "success", "error" => "no_stops"})
    end)

    assert {:ok, :queued} = FrontpadStopRefresh.request_internal(branch.id, :daily)
    refute_received :provider_called
    job = refresh_job(branch.id)
    assert job.queue == "polling"
    assert {:ok, :coalesced} = FrontpadStopRefresh.request_internal(branch.id, :product_rejected)

    Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id), set: [state: "retryable"])

    Repo.update_all(from(s in State, where: s.branch_id == ^branch.id),
      set: [last_attempt_at: DateTime.add(DateTime.utc_now(), -120)]
    )

    assert {:ok, :coalesced} = FrontpadStopRefresh.request_internal(branch.id, :manual)

    assert Repo.aggregate(
             from(j in Oban.Job, where: j.worker == ^Oban.Worker.to_string(RefreshJob)),
             :count
           ) == 1

    assert :ok = RefreshJob.perform(%{job | attempt: 1})
    assert_received :provider_called

    assert %{status: "success", last_good_count: 0, last_success_at: %DateTime{}} =
             FrontpadStopRefresh.state(branch.id)

    assert {:ok, :throttled} = FrontpadStopRefresh.request_internal(branch.id, :manual)
  end

  test "simultaneous requests create one branch job" do
    branch = branch()
    supervisor = start_supervised!(Task.Supervisor)

    results =
      Task.Supervisor.async_stream_nolink(supervisor, 1..2, fn _ ->
        FrontpadStopRefresh.request_internal(branch.id, :manual)
      end)
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.sort(results) == Enum.sort([{:ok, :queued}, {:ok, :coalesced}])

    assert Repo.aggregate(
             from(j in Oban.Job, where: j.worker == ^Oban.Worker.to_string(RefreshJob)),
             :count
           ) == 1
  end

  test "coalescing never rewrites progress or terminal state for the active job" do
    branch = branch()
    assert {:ok, :queued} = FrontpadStopRefresh.request_internal(branch.id, :manual)
    job = refresh_job(branch.id)

    FrontpadStopRefresh.put_state(branch.id, %{
      status: "retrying",
      job_id: job.id,
      last_error: "provider retry"
    })

    before = FrontpadStopRefresh.state(branch.id)
    assert {:ok, :coalesced} = FrontpadStopRefresh.request_internal(branch.id, :daily)
    after_request = FrontpadStopRefresh.state(branch.id)
    assert after_request.status == "retrying"
    assert after_request.last_error == "provider retry"
    assert after_request.updated_at == before.updated_at

    FrontpadStopRefresh.put_state(branch.id, %{status: "success", job_id: job.id})
    terminal = FrontpadStopRefresh.state(branch.id)
    assert {:ok, :throttled} = FrontpadStopRefresh.request_internal(branch.id, :manual)
    assert FrontpadStopRefresh.state(branch.id) == terminal
  end

  test "failure keeps last-good state and existing stops" do
    branch = branch()
    product = insert_branch_product(branch.id, external_id: "101")
    {:ok, _} = Stops.replace_external(branch.id, :frontpad, [product.id])

    FrontpadStopRefresh.put_state(branch.id, %{
      status: "success",
      last_good_count: 1,
      last_good_unlinked: [],
      last_success_at: DateTime.add(DateTime.utc_now(), -120)
    })

    Req.Test.stub(
      Delivest.HTTP.Client,
      &Req.Test.json(&1, %{"result" => "error", "error" => "requests_limit"})
    )

    assert {:ok, :queued} = FrontpadStopRefresh.request_internal(branch.id, :manual)
    job = refresh_job(branch.id)

    assert {:error, :frontpad_stop_refresh_failed} =
             RefreshJob.perform(%{job | attempt: job.max_attempts})

    assert %{
             status: "failed",
             last_good_count: 1,
             last_success_at: %DateTime{},
             last_error: error
           } = FrontpadStopRefresh.state(branch.id)

    assert error == "Frontpad did not respond. Try again later."
    assert Stops.stopped_ids(branch.id) == MapSet.new([product.id])
  end

  test "provider exception becomes a safe retrying state" do
    branch = branch()
    Req.Test.stub(Delivest.HTTP.Client, fn _conn -> raise "secret-api-key" end)
    assert {:ok, :queued} = FrontpadStopRefresh.request_internal(branch.id, :manual)
    job = refresh_job(branch.id)
    assert RefreshJob.timeout(job) == :timer.minutes(2)
    assert {:error, :frontpad_stop_refresh_failed} = RefreshJob.perform(%{job | attempt: 1})

    assert %{status: "retrying", last_error: "Frontpad did not respond. Try again later."} =
             FrontpadStopRefresh.state(branch.id)
  end

  test "disabled Frontpad cannot queue or fetch and old poll targets stop" do
    branch = branch(false)
    other = insert(:branch, is_active: true)

    Repo.insert!(%BranchInfo{
      branch_id: other.id,
      crm: %BranchSettings{
        enabled: true,
        provider: :iiko,
        iiko: %Iiko.Settings{sync_stops: false}
      }
    })

    Req.Test.stub(Delivest.HTTP.Client, fn _conn -> flunk("provider must not be called") end)
    assert {:ok, :disabled} = FrontpadStopRefresh.request_internal(branch.id, :daily)
    refute branch.id in StopPoller.targets()
    assert other.id in StopPoller.targets()
    assert :done = StopPoller.poll(branch.id)
    assert {:ok, :disabled} = StopPoller.poll(other.id)

    assert Repo.aggregate(
             from(j in Oban.Job, where: j.worker == ^Oban.Worker.to_string(RefreshJob)),
             :count
           ) == 0
  end

  test "turning Frontpad stop sync off clears its old stops without HTTP" do
    branch = branch()
    product = insert_branch_product(branch.id, external_id: "101")
    {:ok, _} = Stops.replace_external(branch.id, :frontpad, [product.id])
    staff = insert(:staff, role: insert(:role, permissions: ["integrations.update"]))
    insert(:staff_branch, staff: staff, branch: branch)
    Req.Test.stub(Delivest.HTTP.Client, fn _conn -> flunk("provider must not be called") end)

    assert {:ok, _settings} =
             Crm.update_branch_settings(staff, branch.id, %{
               "enabled" => true,
               "provider" => "frontpad",
               "frontpad" => %{"sync_stops" => false}
             })

    assert Stops.stopped_ids(branch.id) == MapSet.new()
    assert {:ok, :disabled} = FrontpadStopRefresh.request_internal(branch.id, :manual)
  end

  test "manual request requires integration update permission and branch access" do
    branch = branch()
    other = branch()
    reader = insert(:staff, role: insert(:role, permissions: ["integrations.read"]))
    editor = insert(:staff, role: insert(:role, permissions: ["integrations.update"]))
    insert(:staff_branch, staff: reader, branch: branch)
    insert(:staff_branch, staff: editor, branch: branch)
    assert {:error, :forbidden} = FrontpadStopRefresh.request(reader, branch.id)
    assert {:error, :forbidden} = FrontpadStopRefresh.request(editor, other.id)
    assert {:ok, :queued} = FrontpadStopRefresh.request(editor, branch.id)
  end

  test "daily 06:00 uses each branch timezone and schedules one durable dispatch" do
    moscow = branch(true, "Europe/Moscow")
    kamchatka = branch(true, "Asia/Kamchatka")
    disabled = branch(false)
    inactive = branch()
    inactive |> Ecto.Changeset.change(is_active: false) |> Repo.update!()
    task = Registry.task("frontpad_stop_refresh")
    scopes = Registry.scopes(task)
    assert {task, "branch", moscow.id, "Europe/Moscow"} in scopes
    assert {task, "branch", kamchatka.id, "Asia/Kamchatka"} in scopes
    refute Enum.any?(scopes, &(elem(&1, 2) in [disabled.id, inactive.id]))
    assert DispatchWorker.due_at(~D[2026-11-11], "Europe/Moscow", 6) == ~U[2026-11-11 03:00:00Z]
    assert DispatchWorker.due_at(~D[2026-11-11], "Asia/Kamchatka", 6) == ~U[2026-11-10 18:00:00Z]

    assert DispatchWorker.latest_due_date(~U[2026-11-11 03:00:00Z], "Europe/Moscow", 6) ==
             ~D[2026-11-11]

    assert DispatchWorker.latest_due_date(~U[2026-11-11 03:00:00Z], "Asia/Kamchatka", 6) ==
             ~D[2026-11-11]

    assert {:ok, :scheduled} = DispatchWorker.schedule(task, "branch", moscow.id, ~D[2026-11-11])
    assert {:ok, :already} = DispatchWorker.schedule(task, "branch", moscow.id, ~D[2026-11-11])
    run = Repo.one!(from(r in DailyRun, where: r.scope_id == ^moscow.id))
    assert :ok = DailyJob.perform(Repo.get!(Oban.Job, run.job_id))
    assert {:ok, :coalesced} = FrontpadStopRefresh.request_internal(moscow.id, :daily)

    assert Repo.aggregate(
             from(j in Oban.Job, where: j.worker == ^Oban.Worker.to_string(RefreshJob)),
             :count
           ) == 1
  end
end
