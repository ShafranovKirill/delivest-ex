defmodule DelivestWeb.Staff.IntegrationLive.FrontpadStopRefreshTest do
  use DelivestWeb.ConnCase, async: false
  use Oban.Testing, repo: Delivest.Repo

  import Phoenix.LiveViewTest
  import Delivest.Factory
  import Ecto.Query

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Crm.BranchSettings
  alias Delivest.Integrations.Crm.FrontpadStopRefresh.{RefreshJob, State}
  alias Delivest.Integrations.Frontpad

  defp page(conn) do
    branch = insert(:branch, is_active: true)

    Delivest.Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{
        enabled: true,
        provider: :frontpad,
        frontpad: %Frontpad.Settings{api_key: "key", sync_stops: true}
      }
    })

    staff =
      insert(:staff,
        role: insert(:role, permissions: ["integrations.read", "integrations.update"])
      )

    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id})
    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/integrations/frontpad")
    render_hook(view, "tab", %{"tab" => "settings"})
    {view, branch, conn}
  end

  test "manual refresh is pending, then shows success and persists last good result", %{
    conn: conn
  } do
    {view, branch, _conn} = page(conn)

    Req.Test.stub(
      Delivest.HTTP.Client,
      &Req.Test.json(&1, %{"result" => "success", "error" => "no_stops"})
    )

    render_hook(view, "sync_stops", %{})
    assert has_element?(view, "#frontpad-stops-pending")
    assert has_element?(view, "#frontpad-sync-stops[disabled]")

    job =
      Delivest.Repo.one!(
        from(j in Oban.Job, where: j.worker == ^Oban.Worker.to_string(RefreshJob))
      )

    assert :ok = RefreshJob.perform(%{job | attempt: 1})
    render(view)
    assert has_element?(view, "#frontpad-stops", "products in stop: 0")
    refute has_element?(view, "#frontpad-stops-pending")
    assert %{last_good_count: 0, status: "success"} = Delivest.Repo.get!(State, branch.id)
  end

  test "failed refresh keeps last good count visible after reload", %{conn: conn} do
    {view, branch, conn} = page(conn)

    Req.Test.stub(
      Delivest.HTTP.Client,
      &Req.Test.json(&1, %{"result" => "success", "error" => "no_stops"})
    )

    render_hook(view, "sync_stops", %{})

    job =
      Delivest.Repo.one!(
        from(j in Oban.Job, where: j.worker == ^Oban.Worker.to_string(RefreshJob))
      )

    assert :ok = RefreshJob.perform(%{job | attempt: 1})
    render(view)

    Delivest.Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id),
      set: [state: "completed"]
    )

    Delivest.Repo.update_all(from(s in State, where: s.branch_id == ^branch.id),
      set: [last_attempt_at: DateTime.add(DateTime.utc_now(), -61)]
    )

    Req.Test.stub(
      Delivest.HTTP.Client,
      &Req.Test.json(&1, %{"result" => "error", "error" => "requests_limit"})
    )

    render_hook(view, "sync_stops", %{})

    failed_job =
      Delivest.Repo.one!(
        from(j in Oban.Job,
          where: j.worker == ^Oban.Worker.to_string(RefreshJob) and j.id != ^job.id
        )
      )

    assert {:error, :frontpad_stop_refresh_failed} =
             RefreshJob.perform(%{failed_job | attempt: failed_job.max_attempts})

    render(view)
    assert has_element?(view, "#frontpad-stops-error")
    assert has_element?(view, "#frontpad-stops", "products in stop: 0")
    {:ok, reloaded, _} = live(conn, ~p"/staff/b/#{branch}/integrations/frontpad")
    render_hook(reloaded, "tab", %{"tab" => "settings"})
    assert has_element?(reloaded, "#frontpad-stops-error")
    assert has_element?(reloaded, "#frontpad-stops", "products in stop: 0")
  end

  test "status tick reconciles a discarded job and unlocks manual refresh", %{conn: conn} do
    {view, branch, _conn} = page(conn)
    render_hook(view, "sync_stops", %{})

    job =
      Delivest.Repo.one!(
        from(j in Oban.Job, where: j.worker == ^Oban.Worker.to_string(RefreshJob))
      )

    Delivest.Repo.update_all(from(s in State, where: s.branch_id == ^branch.id),
      set: [
        status: "running",
        last_good_count: 2,
        last_good_unlinked: [],
        last_success_at: DateTime.add(DateTime.utc_now(), -120)
      ]
    )

    Delivest.Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id),
      set: [state: "discarded"]
    )

    send(view.pid, :stop_refresh_tick)
    render(view)

    assert has_element?(view, "#frontpad-stops-error")
    assert has_element?(view, "#frontpad-stops", "products in stop: 2")
    assert has_element?(view, "#frontpad-sync-stops:not([disabled])")
    assert %{status: "failed", last_good_count: 2} = Delivest.Repo.get!(State, branch.id)
  end
end
