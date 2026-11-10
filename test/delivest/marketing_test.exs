defmodule Delivest.MarketingTest do
  use Delivest.DataCase, async: false
  use Oban.Testing, repo: Delivest.Repo
  import Delivest.Factory

  alias Delivest.{Background, Features, Marketing, Repo, Segments}
  alias Delivest.Background.{Runner, Schedule}
  alias Delivest.Marketing.{Issue, Policy}
  alias Delivest.Oms.{Order, OrderTransition}
  alias Delivest.OrderFixtures

  setup do
    branch = insert(:branch, is_active: true)
    client = insert(:client)

    staff =
      insert(:staff,
        role:
          insert(:role,
            permissions:
              ~w(segments.read segments.manage marketing.read marketing.manage marketing.reports)
          )
      )

    insert(:staff_branch, staff: staff, branch: branch)
    staff = Repo.preload(staff, [:role, :branches])
    {:ok, _} = Features.configure("marketing_policies", :franchise, true, actor: "test")
    {:ok, _} = Features.configure("marketing_policies", {:branch, branch.id}, true, actor: "test")
    promotion = insert_promotion(branch.id, kind: :personal_code, rules: "then discount 10%")
    %{branch: branch, client: client, staff: staff, promotion: promotion}
  end

  test "preview is async, activation requires it, and a unique issue owns reward and notice",
       ctx do
    old_order = completed_order(ctx, 31)

    {:ok, segment} =
      Segments.create(ctx.staff, %{name: "Dormant", kind: :manual, scope: :branches}, [
        ctx.branch.id
      ])

    assert :ok = Segments.add_member(ctx.staff, segment.id, ctx.client.id)

    {:ok, policy} =
      Marketing.create(ctx.staff, attrs(ctx, segment, "all_current"), [ctx.branch.id])

    assert {:error, :preview_required} = Marketing.activate(ctx.staff, policy.id, policy.revision)
    assert {:ok, %{status: :pending}} = Marketing.preview(ctx.staff, policy.id)
    assert {:ok, count} = Background.dispatch_due()
    assert count >= 1
    schedule = Repo.get_by!(Schedule, kind: "marketing.preview")
    assert :ok = Runner.perform(Repo.get!(Oban.Job, schedule.current_job_id))
    assert {:ok, %{status: :ready, eligible_clients: 1}} = Marketing.preview(ctx.staff, policy.id)
    assert {:ok, active} = Marketing.activate(ctx.staff, policy.id, policy.revision)
    assert active.status == :active

    context = issue_context()
    assert {:ok, %Issue{} = issue} = Marketing.issue(active, ctx.client.id, context)
    assert issue.cycle_order_id == old_order.id
    assert {:ok, :skipped} = Marketing.issue(active, ctx.client.id, context)
    assert Repo.aggregate(Issue, :count) == 1
    assert Repo.aggregate(Delivest.Promo.PromoCode, :count) == 1
    assert Repo.aggregate(Delivest.Notifications.Notification, :count) == 1
    assert Marketing.notification_current?(issue.id, ctx.client.id, :show)

    assert MapSet.member?(
             Marketing.notification_current_many?([issue.id], ctx.client.id, :show),
             issue.id
           )

    new_order =
      OrderFixtures.order_fixture(ctx.branch.id,
        attrs: %{"customer_phone" => ctx.client.phone}
      )

    assert Marketing.notification_current?(issue.id, ctx.client.id, :show)

    assert MapSet.member?(
             Marketing.notification_current_many?([issue.id], ctx.client.id, :show),
             issue.id
           )

    assert {:ok, :skipped} = Marketing.issue(active, ctx.client.id, context)
    Repo.update_all(from(o in Order, where: o.id == ^new_order.id), set: [status: :completed])

    Repo.insert!(%OrderTransition{
      order_id: new_order.id,
      from: :created,
      to: :completed,
      source: :staff,
      inserted_at: DateTime.utc_now(:microsecond)
    })

    refute Marketing.notification_current?(issue.id, ctx.client.id, :show)

    refute MapSet.member?(
             Marketing.notification_current_many?([issue.id], ctx.client.id, :show),
             issue.id
           )
  end

  test "future-only freezes the manual cohort and allows a new completed-order cycle", ctx do
    completed_order(ctx, 31)

    {:ok, segment} =
      Segments.create(ctx.staff, %{name: "Future cohort", kind: :manual, scope: :branches}, [
        ctx.branch.id
      ])

    assert :ok = Segments.add_member(ctx.staff, segment.id, ctx.client.id)

    {:ok, policy} =
      Marketing.create(ctx.staff, attrs(ctx, segment, "future_only"), [ctx.branch.id])

    assert {:ok, %{status: :pending}} = Marketing.preview(ctx.staff, policy.id)

    [[first_request]] =
      Repo.query!(
        "SELECT request_id FROM marketing_previews WHERE policy_id=$1",
        [Ecto.UUID.dump!(policy.id)]
      ).rows

    assert {:ok, %{status: :pending}} = Marketing.preview(ctx.staff, policy.id)

    assert Repo.query!(
             "SELECT request_id FROM marketing_previews WHERE policy_id=$1",
             [Ecto.UUID.dump!(policy.id)]
           ).rows == [[first_request]]

    assert {:ok, _} = Background.dispatch_due()
    run_task("marketing.preview")
    assert {:ok, %{status: :ready, eligible_clients: 1}} = Marketing.preview(ctx.staff, policy.id)
    assert {:ok, initializing} = Marketing.activate(ctx.staff, policy.id, policy.revision)
    assert initializing.status == :initializing

    assert Repo.query!(
             "SELECT count(*) FROM marketing_baseline_members WHERE policy_id=$1",
             [Ecto.UUID.dump!(policy.id)]
           ).rows == [[1]]

    assert {:snooze, 1} = run_task("marketing.evaluate")
    active = Repo.get!(Delivest.Marketing.Policy, policy.id)
    assert active.status == :active
    assert {:ok, :skipped} = Marketing.issue(active, ctx.client.id, issue_context())
    assert Repo.aggregate(Issue, :count) == 0

    new_order =
      OrderFixtures.order_fixture(ctx.branch.id,
        attrs: %{"customer_phone" => ctx.client.phone}
      )

    Repo.update_all(from(o in Order, where: o.id == ^new_order.id),
      set: [status: :completed, client_id: ctx.client.id]
    )

    Repo.insert!(%OrderTransition{
      order_id: new_order.id,
      from: :created,
      to: :completed,
      source: :staff,
      inserted_at: DateTime.utc_now(:microsecond)
    })

    later = DateTime.add(DateTime.utc_now(:second), 31 * 86_400, :second)

    assert {:ok, %Issue{cycle_order_id: cycle_id}} =
             Marketing.issue(active, ctx.client.id, issue_context(), later)

    assert cycle_id == new_order.id
  end

  test "feature generation invalidates a ready preview", ctx do
    completed_order(ctx, 31)

    {:ok, segment} =
      Segments.create(ctx.staff, %{name: "Generation cohort", kind: :manual, scope: :branches}, [
        ctx.branch.id
      ])

    assert :ok = Segments.add_member(ctx.staff, segment.id, ctx.client.id)

    {:ok, policy} =
      Marketing.create(ctx.staff, attrs(ctx, segment, "all_current"), [ctx.branch.id])

    assert {:ok, %{status: :pending}} = Marketing.preview(ctx.staff, policy.id)

    [[first_request]] =
      Repo.query!(
        "SELECT request_id FROM marketing_previews WHERE policy_id=$1",
        [Ecto.UUID.dump!(policy.id)]
      ).rows

    assert {:ok, %{status: :pending}} = Marketing.preview(ctx.staff, policy.id)

    assert Repo.query!(
             "SELECT request_id FROM marketing_previews WHERE policy_id=$1",
             [Ecto.UUID.dump!(policy.id)]
           ).rows == [[first_request]]

    assert {:ok, _} = Background.dispatch_due()
    run_task("marketing.preview")
    assert {:ok, %{status: :ready}} = Marketing.preview(ctx.staff, policy.id)

    assert {:ok, _} = Features.configure("marketing_policies", :franchise, false, actor: "test")
    assert {:ok, _} = Features.configure("marketing_policies", :franchise, true, actor: "test")
    assert {:error, :preview_required} = Marketing.activate(ctx.staff, policy.id, policy.revision)
    assert {:ok, %{status: :pending}} = Marketing.preview(ctx.staff, policy.id)

    [[next_request]] =
      Repo.query!(
        "SELECT request_id FROM marketing_previews WHERE policy_id=$1",
        [Ecto.UUID.dump!(policy.id)]
      ).rows

    refute next_request == first_request

    assert Repo.query!(
             "SELECT count(*) FROM marketing_baseline_members WHERE policy_id=$1 AND request_id=$2",
             [Ecto.UUID.dump!(policy.id), first_request]
           ).rows == [[0]]
  end

  test "future-only stores only eligible preview cycles and never suppresses a later cycle",
       ctx do
    old = completed_order(ctx, 31)
    recent = insert(:client)
    recent_order = OrderFixtures.order_fixture(ctx.branch.id)

    Repo.update_all(from(o in Order, where: o.id == ^recent_order.id),
      set: [status: :completed, client_id: recent.id]
    )

    Repo.insert!(%OrderTransition{
      order_id: recent_order.id,
      from: :created,
      to: :completed,
      source: :staff,
      inserted_at: DateTime.utc_now(:microsecond)
    })

    {:ok, segment} =
      Segments.create(
        ctx.staff,
        %{name: "Frozen eligible cohort", kind: :manual, scope: :branches},
        [ctx.branch.id]
      )

    assert :ok = Segments.add_member(ctx.staff, segment.id, ctx.client.id)
    assert :ok = Segments.add_member(ctx.staff, segment.id, recent.id)

    {:ok, policy} =
      Marketing.create(ctx.staff, attrs(ctx, segment, "future_only"), [ctx.branch.id])

    assert {:ok, %{status: :pending}} = Marketing.preview(ctx.staff, policy.id)
    assert {:ok, _} = Background.dispatch_due()
    run_task("marketing.preview")
    assert {:ok, %{status: :ready, eligible_clients: 1}} = Marketing.preview(ctx.staff, policy.id)

    [[frozen_raw]] =
      Repo.query!(
        "SELECT cycle_order_id FROM marketing_baseline_members WHERE policy_id=$1",
        [Ecto.UUID.dump!(policy.id)]
      ).rows

    assert Ecto.UUID.load!(frozen_raw) == old.id

    new_order = OrderFixtures.order_fixture(ctx.branch.id)

    Repo.update_all(from(o in Order, where: o.id == ^new_order.id),
      set: [status: :completed, client_id: ctx.client.id]
    )

    Repo.insert!(%OrderTransition{
      order_id: new_order.id,
      from: :created,
      to: :completed,
      source: :staff,
      inserted_at: DateTime.utc_now(:microsecond)
    })

    {:ok, _} = Marketing.activate(ctx.staff, policy.id, policy.revision)
    assert {:snooze, 1} = run_task("marketing.evaluate")

    [[suppressed_raw]] =
      Repo.query!(
        "SELECT cycle_order_id FROM marketing_suppressions WHERE policy_id=$1",
        [Ecto.UUID.dump!(policy.id)]
      ).rows

    assert Ecto.UUID.load!(suppressed_raw) == old.id
  end

  test "candidate selection uses a fixed number of SQL queries for 5 and 50 clients", ctx do
    {:ok, segment} =
      Segments.create(ctx.staff, %{name: "Batch candidates", kind: :manual, scope: :branches}, [
        ctx.branch.id
      ])

    {:ok, policy} =
      Marketing.create(ctx.staff, attrs(ctx, segment, "all_current"), [ctx.branch.id])

    ids = for _ <- 1..50, do: insert(:client).id
    now = DateTime.utc_now(:second)

    {five, result5} =
      count_queries(fn -> Marketing.candidate_state(policy, Enum.take(ids, 5), now) end)

    {fifty, result50} = count_queries(fn -> Marketing.candidate_state(policy, ids, now) end)
    assert result5.eligible_ids == [] and result50.eligible_ids == []
    assert five > 0
    assert five == fifty
  end

  test "used segment membership requires current impact and revision; no-op is idempotent", ctx do
    completed_order(ctx, 31)

    {:ok, segment} =
      Segments.create(ctx.staff, %{name: "Protected members", kind: :manual, scope: :branches}, [
        ctx.branch.id
      ])

    assert :ok = Segments.add_member(ctx.staff, segment.id, ctx.client.id)

    {:ok, policy} =
      Marketing.create(ctx.staff, attrs(ctx, segment, "all_current"), [ctx.branch.id])

    assert {:ok, %{status: :pending}} = Marketing.preview(ctx.staff, policy.id)
    assert {:ok, _} = Background.dispatch_due()
    run_task("marketing.preview")
    assert {:ok, _} = Marketing.activate(ctx.staff, policy.id, policy.revision)

    revision = Repo.reload!(segment).revision

    assert {:error, {:policy_confirmation_required, impact}} =
             Segments.remove_member(ctx.staff, segment.id, ctx.client.id)

    assert Enum.any?(impact.policies, &(&1.id == policy.id))
    assert Repo.reload!(segment).revision == revision

    assert {:error, {:policy_confirmation_required, _}} =
             Segments.remove_member(ctx.staff, segment.id, ctx.client.id, %{
               expected_revision: revision,
               policy_confirmation: "stale"
             })

    assert :ok =
             Segments.remove_member(ctx.staff, segment.id, ctx.client.id, %{
               expected_revision: revision,
               policy_confirmation: impact.fingerprint
             })

    assert Repo.reload!(segment).revision == revision + 1
    assert :ok = Segments.remove_member(ctx.staff, segment.id, ctx.client.id)
    assert Repo.reload!(segment).revision == revision + 1
  end

  test "notice currentness reads 5 and 31 policies with fixed SQL query count", ctx do
    order = completed_order(ctx, 31)
    {:ok, token} = Features.snapshot("marketing_policies", {:branch, ctx.branch.id})

    segment =
      Repo.insert!(%Delivest.Segments.Segment{
        name: "Notice batch",
        kind: :manual,
        scope: :branches
      })

    issues =
      for index <- 1..31 do
        policy =
          Repo.insert!(%Policy{
            name: "Notice policy #{index}",
            segment_id: segment.id,
            scope: :branches,
            reward_branch_id: ctx.branch.id,
            bonus_amount: 1,
            inactivity_days: 1,
            reward_ttl_days: 7,
            attribution_days: 7,
            status: :active,
            message_title: "Notice",
            message_body: "Text"
          })

        Repo.insert_all("marketing_policy_branches", [
          %{policy_id: Ecto.UUID.dump!(policy.id), branch_id: Ecto.UUID.dump!(ctx.branch.id)}
        ])

        Repo.insert!(%Issue{
          policy_id: policy.id,
          client_id: ctx.client.id,
          cycle_order_id: order.id,
          branch_id: ctx.branch.id,
          reward_type: "bonus",
          reward_id: Ecto.UUID.generate(),
          reward_amount: 1,
          issued_at: DateTime.utc_now(:second),
          expires_at: DateTime.add(DateTime.utc_now(:second), 7 * 86_400, :second),
          attribution_until: DateTime.add(DateTime.utc_now(:second), 7 * 86_400, :second),
          policy_revision: 1,
          source_generation_franchise: token.franchise,
          source_generation_branch: token.branch
        })
      end

    {five, _} =
      count_queries(fn ->
        Marketing.notification_current_many?(
          Enum.take(Enum.map(issues, & &1.id), 5),
          ctx.client.id,
          :show
        )
      end)

    {thirty_one, _} =
      count_queries(fn ->
        Marketing.notification_current_many?(Enum.map(issues, & &1.id), ctx.client.id, :show)
      end)

    assert five > 0
    assert five == thirty_one
  end

  test "issue rejects stale planner owner and original generation after feature restart", ctx do
    completed_order(ctx, 31)

    {:ok, segment} =
      Segments.create(ctx.staff, %{name: "Fenced issue", kind: :manual, scope: :branches}, [
        ctx.branch.id
      ])

    assert :ok = Segments.add_member(ctx.staff, segment.id, ctx.client.id)

    {:ok, policy} =
      Marketing.create(ctx.staff, attrs(ctx, segment, "all_current"), [ctx.branch.id])

    assert {:ok, %{status: :pending}} = Marketing.preview(ctx.staff, policy.id)
    assert {:ok, _} = Background.dispatch_due()
    run_task("marketing.preview")
    {:ok, active} = Marketing.activate(ctx.staff, policy.id, policy.revision)

    old = issue_context()

    Repo.update_all(from(s in Schedule, where: s.id == ^old.schedule_id),
      set: [current_job_id: old.job_id + 1]
    )

    assert {:error, :disabled} = Marketing.issue(active, ctx.client.id, old)
    assert Repo.aggregate(Issue, :count) == 0

    original = issue_context()
    assert {:ok, _} = Features.configure("marketing_policies", :franchise, false, actor: "test")
    assert {:ok, _} = Features.configure("marketing_policies", :franchise, true, actor: "test")
    assert {:error, :disabled} = Marketing.issue(active, ctx.client.id, original)
    assert Repo.aggregate(Issue, :count) == 0
  end

  test "atom-key policy attributes retain the selected promotion", ctx do
    {:ok, segment} =
      Segments.create(ctx.staff, %{name: "Atom policy", kind: :manual, scope: :branches}, [
        ctx.branch.id
      ])

    atom_attrs =
      attrs(ctx, segment, "all_current")
      |> Map.new(fn {key, value} -> {String.to_existing_atom(key), value} end)

    assert {:ok, policy} = Marketing.create(ctx.staff, atom_attrs, [ctx.branch.id])
    assert policy.promotion_id == ctx.promotion.id
  end

  test "paused initializing policy retains frozen baseline through preview cleanup", ctx do
    old = completed_order(ctx, 31)

    {:ok, segment} =
      Segments.create(ctx.staff, %{name: "Paused baseline", kind: :manual, scope: :branches}, [
        ctx.branch.id
      ])

    assert :ok = Segments.add_member(ctx.staff, segment.id, ctx.client.id)

    {:ok, policy} =
      Marketing.create(ctx.staff, attrs(ctx, segment, "future_only"), [ctx.branch.id])

    assert {:ok, %{status: :pending}} = Marketing.preview(ctx.staff, policy.id)
    assert {:ok, _} = Background.dispatch_due()
    run_task("marketing.preview")
    {:ok, initializing} = Marketing.activate(ctx.staff, policy.id, policy.revision)
    {:ok, paused} = Marketing.pause(ctx.staff, policy.id, initializing.revision)
    assert :ok = Delivest.Marketing.Preview.perform(:franchise, task_context("marketing.preview"))

    assert Repo.query!(
             "SELECT count(*) FROM marketing_baseline_members WHERE policy_id=$1",
             [Ecto.UUID.dump!(policy.id)]
           ).rows == [[1]]

    {:ok, resumed} = Marketing.activate(ctx.staff, policy.id, paused.revision)
    assert resumed.status == :initializing
    assert {:snooze, 1} = run_task("marketing.evaluate")

    [[cycle_raw]] =
      Repo.query!(
        "SELECT cycle_order_id FROM marketing_suppressions WHERE policy_id=$1",
        [Ecto.UUID.dump!(policy.id)]
      ).rows

    assert Ecto.UUID.load!(cycle_raw) == old.id
  end

  defp run_task(kind) do
    schedule = Repo.get_by!(Schedule, kind: kind)
    Runner.perform(Repo.get!(Oban.Job, schedule.current_job_id))
  end

  defp issue_context, do: task_context("marketing.evaluate")

  defp task_context(kind) do
    {:ok, token} = Features.snapshot("marketing_policies", :franchise)
    schedule = Repo.get_by!(Schedule, kind: kind, scope_key: "franchise")

    job =
      Repo.insert!(%Oban.Job{
        worker: "Delivest.Background.Runner",
        queue: "background",
        args: %{"kind" => kind},
        state: "executing",
        max_attempts: 1
      })

    Repo.update!(Ecto.Changeset.change(schedule, running: true, current_job_id: job.id))

    %{
      feature: "marketing_policies",
      scope: :franchise,
      generation: token,
      schedule_id: schedule.id,
      job_id: job.id
    }
  end

  defp count_queries(fun) do
    id = "marketing-query-count-#{System.unique_integer([:positive])}"
    pid = self()

    :ok =
      :telemetry.attach(
        id,
        [:delivest, :repo, :query],
        fn _event, _measurements, _metadata, _config -> send(pid, {:marketing_query, id}) end,
        nil
      )

    result = fun.()
    :ok = :telemetry.detach(id)
    {drain_queries(id, 0), result}
  end

  defp drain_queries(id, count) do
    receive do
      {:marketing_query, ^id} -> drain_queries(id, count + 1)
    after
      0 -> count
    end
  end

  defp attrs(ctx, segment, mode) do
    %{
      "name" => "Return offer",
      "scope" => "branches",
      "segment_id" => segment.id,
      "reward_branch_id" => ctx.branch.id,
      "promotion_id" => ctx.promotion.id,
      "inactivity_days" => 30,
      "reward_ttl_days" => 14,
      "attribution_days" => 7,
      "initial_mode" => mode,
      "channels" => ["in_app"],
      "message_title" => "Come back",
      "message_body" => "Your offer is ready"
    }
  end

  defp completed_order(ctx, days_ago) do
    order =
      OrderFixtures.order_fixture(ctx.branch.id,
        attrs: %{"customer_phone" => ctx.client.phone}
      )

    Repo.update_all(from(o in Order, where: o.id == ^order.id),
      set: [status: :completed, client_id: ctx.client.id]
    )

    at = DateTime.add(DateTime.utc_now(:microsecond), -days_ago * 86_400, :second)

    Repo.insert!(%OrderTransition{
      order_id: order.id,
      from: :created,
      to: :completed,
      source: :staff,
      inserted_at: at
    })

    order
  end
end
