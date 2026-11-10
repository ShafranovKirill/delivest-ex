defmodule Delivest.BackgroundTest do
  use Delivest.DataCase, async: false
  use Oban.Testing, repo: Delivest.Repo

  import Ecto.Query
  alias Delivest.{Background, Features, Repo}
  alias Delivest.Background.{Runner, Schedule}

  test "disabled installation has no work; due scheduling coalesces" do
    assert {:ok, 0} = Background.dispatch_due()
    refute_enqueued(worker: Runner)

    assert {:ok, _} = Features.configure("segments", :franchise, true, actor: "host")
    assert {:ok, 1} = Background.dispatch_due()
    assert {:ok, 0} = Background.dispatch_due()
    assert_enqueued(worker: Runner)
    assert Repo.one!(Schedule).running
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
    assert {:ok, _} = Features.configure("segments", :franchise, false, actor: "host")
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
    Background.record_error(first.kind, first.scope_key, first.current_job_id)
    assert Repo.one!(Schedule).last_error_at

    Repo.update_all(from(j in Oban.Job, where: j.id == ^first.current_job_id),
      set: [state: "discarded"]
    )

    assert {:ok, 0} = Background.dispatch_due()
    recovered = Repo.one!(Schedule)
    refute recovered.running
    assert is_nil(recovered.current_job_id)
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
    assert {:ok, _} = Features.configure("segments", {:branch, branch.id}, true, actor: "host")
    refute Background.still_enabled?(context)
    assert {:error, :disabled} = Background.publish(context, fn -> flunk("old run wrote") end)
    assert is_nil(Repo.reload!(old).current_job_id)
  end
end
