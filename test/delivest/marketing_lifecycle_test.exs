defmodule Delivest.MarketingLifecycleTest do
  use Delivest.DataCase, async: false
  use Oban.Testing, repo: Delivest.Repo
  import Delivest.Factory
  import Ecto.Query

  alias Delivest.{Background, Features, Marketing, Repo, Segments}
  alias Delivest.Background.{Runner, Schedule}
  alias Delivest.Identity.Branch.{BranchInfo, LoyaltySettings}
  alias Delivest.Marketing.{Issue, Policy, Report}
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
              ~w(segments.read segments.manage marketing.read marketing.manage marketing.delete marketing.reports)
          )
      )

    insert(:staff_branch, staff: staff, branch: branch)
    staff = Repo.preload(staff, [:role, :branches])
    {:ok, _} = Features.configure("marketing_policies", :franchise, true, actor: "test")
    {:ok, _} = Features.configure("marketing_policies", {:branch, branch.id}, true, actor: "test")
    promotion = insert_promotion(branch.id, kind: :personal_code, rules: "then discount 10%")
    %{branch: branch, client: client, staff: staff, promotion: promotion}
  end

  test "draft deletion removes policy-owned records and blocks stale report requests", ctx do
    policy = create_policy(ctx)
    order = completed_order(ctx, 31)
    now = DateTime.utc_now(:second)

    for table <- ["marketing_suppressions", "marketing_exclusions"] do
      Repo.insert_all(table, [
        %{
          policy_id: Ecto.UUID.dump!(policy.id),
          client_id: Ecto.UUID.dump!(ctx.client.id),
          cycle_order_id: Ecto.UUID.dump!(order.id),
          reason: "test",
          inserted_at: now
        }
      ])
    end

    assert {:ok, %{status: :pending}} = Marketing.preview(ctx.staff, policy.id)
    assert {:ok, %{status: :pending}} = Marketing.report(ctx.staff, policy.id)
    assert {:ok, :deleted} = Marketing.delete(ctx.staff, policy.id, policy.revision)
    assert Repo.get(Policy, policy.id) == nil

    for table <- [
          "marketing_previews",
          "marketing_report_requests",
          "marketing_policy_audits",
          "marketing_suppressions",
          "marketing_exclusions"
        ] do
      assert [[0]] =
               Repo.query!("SELECT count(*) FROM #{table} WHERE policy_id=$1", [
                 Ecto.UUID.dump!(policy.id)
               ]).rows
    end

    assert {:error, :stale} = Report.request(policy)
    assert :ok = Delivest.Marketing.Preview.perform(:franchise, task_context("marketing.preview"))
    assert {:error, :not_found} = Marketing.get(ctx.staff, policy.id)
  end

  test "started policy is archived, remains reportable, and cannot resume or issue", ctx do
    policy = create_policy(ctx)

    started =
      Repo.update!(
        Ecto.Changeset.change(policy,
          status: :active,
          activated_at: DateTime.utc_now(:second)
        )
      )

    assert {:ok, :archived} = Marketing.delete(ctx.staff, started.id, started.revision)
    assert {:ok, archived} = Marketing.get(ctx.staff, started.id)
    assert archived.status == :paused
    assert archived.deleted_at
    assert archived.revision == started.revision + 1
    assert {:ok, []} = Marketing.list(ctx.staff)
    assert Marketing.segment_impact(started.segment_id).policies == []
    assert {:ok, [%Policy{id: id}]} = Marketing.list(ctx.staff, deleted: :only)
    assert id == started.id
    assert {:ok, %{status: :pending}} = Marketing.report(ctx.staff, started.id)
    assert {:error, :stale} = Marketing.activate(ctx.staff, started.id, archived.revision)

    assert {:error, :stale} =
             Marketing.update(
               ctx.staff,
               started.id,
               attrs(ctx, archived),
               [ctx.branch.id],
               [],
               []
             )

    assert {:error, :stale} = Marketing.delete(ctx.staff, started.id, archived.revision)
  end

  test "paused edit preserves prior promo reward and lifetime issued count", ctx do
    Repo.insert!(%BranchInfo{
      branch_id: ctx.branch.id,
      loyalty: %LoyaltySettings{enabled: true}
    })

    Cachex.del(:branch_cache, ctx.branch.id)

    assert Delivest.Loyalty.enabled?(ctx.branch.id)

    completed_order(ctx, 31)
    policy = create_policy(ctx, "all_current")
    {:ok, segment} = Segments.get(ctx.staff, policy.segment_id)
    assert :ok = Segments.add_member(ctx.staff, segment.id, ctx.client.id)
    assert {:ok, %{status: :pending}} = Marketing.preview(ctx.staff, policy.id)
    assert {:ok, _} = Background.dispatch_due()
    run_task("marketing.preview")
    assert {:ok, active} = Marketing.activate(ctx.staff, policy.id, policy.revision)
    assert {:ok, %Issue{} = issue} = Marketing.issue(active, ctx.client.id, issue_context())
    assert Marketing.notification_current?(issue.id, ctx.client.id, :show)
    assert {:ok, paused} = Marketing.pause(ctx.staff, policy.id, active.revision)

    attrs =
      attrs(ctx, paused)
      |> Map.put("promotion_id", nil)
      |> Map.put("bonus_amount", 50)
      |> Map.put("message_title", "A new offer")
      |> Map.put("max_issues", 1)

    assert {:ok, edited} = Marketing.update(ctx.staff, policy.id, attrs, [ctx.branch.id], [], [])
    assert edited.promotion_id == nil
    assert edited.bonus_amount == 50
    assert edited.issued_count == 1
    assert edited.activated_at == active.activated_at
    assert edited.cursor_client_id == nil
    assert edited.evaluated_run_id == nil

    assert {:error, :immutable_initial_mode} =
             Marketing.update(
               ctx.staff,
               policy.id,
               %{attrs | "expected_revision" => edited.revision, "initial_mode" => "future_only"},
               [ctx.branch.id],
               [],
               []
             )

    other_branch = insert(:branch, is_active: true)
    insert(:staff_branch, staff: ctx.staff, branch: other_branch)

    {:ok, _} =
      Features.configure("marketing_policies", {:branch, other_branch.id}, true, actor: "test")

    other_staff = Repo.preload(ctx.staff, :branches, force: true)

    other_promotion =
      insert_promotion(other_branch.id, kind: :personal_code, rules: "then discount 10%")

    {:ok, other_segment} =
      Segments.create(
        other_staff,
        %{name: "Other audience", kind: :manual, scope: :branches},
        [other_branch.id]
      )

    different_scope =
      attrs
      |> Map.put("expected_revision", edited.revision)
      |> Map.put("segment_id", other_segment.id)
      |> Map.put("reward_branch_id", other_branch.id)
      |> Map.put("promotion_id", other_promotion.id)
      |> Map.put("bonus_amount", nil)

    assert {:error, :immutable_policy_scope} =
             Marketing.update(other_staff, policy.id, different_scope, [other_branch.id], [], [])

    assert {:ok, resumed} = Marketing.activate(ctx.staff, policy.id, edited.revision)
    assert Marketing.notification_current?(issue.id, ctx.client.id, :show)

    assert MapSet.member?(
             Marketing.notification_current_many?([issue.id], ctx.client.id, :show),
             issue.id
           )

    assert {:ok, :skipped} = Marketing.issue(resumed, ctx.client.id, issue_context())
    assert Repo.aggregate(Issue, :count) == 1
    assert {:ok, :archived} = Marketing.delete(ctx.staff, policy.id, resumed.revision)
    assert Marketing.notification_current?(issue.id, ctx.client.id, :show)
    refute Marketing.notification_current?(issue.id, ctx.client.id, :send)

    assert MapSet.member?(
             Marketing.notification_current_many?([issue.id], ctx.client.id, :show),
             issue.id
           )

    assert {:error, :stale} = Marketing.issue(resumed, ctx.client.id, issue_context())
  end

  test "paused initializing edit keeps the frozen baseline", ctx do
    completed_order(ctx, 31)
    policy = create_policy(ctx, "future_only")
    {:ok, segment} = Segments.get(ctx.staff, policy.segment_id)
    assert :ok = Segments.add_member(ctx.staff, segment.id, ctx.client.id)
    assert {:ok, %{status: :pending}} = Marketing.preview(ctx.staff, policy.id)
    assert {:ok, _} = Background.dispatch_due()
    run_task("marketing.preview")
    assert {:ok, initializing} = Marketing.activate(ctx.staff, policy.id, policy.revision)
    assert initializing.status == :initializing
    assert {:ok, paused} = Marketing.pause(ctx.staff, policy.id, initializing.revision)

    changed = Map.put(attrs(ctx, paused), "message_title", "Updated while paused")

    assert {:ok, edited} =
             Marketing.update(ctx.staff, policy.id, changed, [ctx.branch.id], [], [])

    assert edited.baseline_snapshot_id == paused.baseline_snapshot_id
    assert edited.baseline_complete == false
    assert edited.cursor_client_id == paused.cursor_client_id
    assert edited.activated_at == paused.activated_at
    assert :ok = Delivest.Marketing.Preview.perform(:franchise, task_context("marketing.preview"))

    assert [[1]] =
             Repo.query!("SELECT count(*) FROM marketing_baseline_members WHERE policy_id=$1", [
               Ecto.UUID.dump!(policy.id)
             ]).rows

    assert {:ok, resumed} = Marketing.activate(ctx.staff, policy.id, edited.revision)
    assert resumed.status == :initializing
    assert resumed.baseline_snapshot_id == paused.baseline_snapshot_id
  end

  test "delete permission, stale revision, and feature gate are enforced", ctx do
    policy = create_policy(ctx)

    no_delete =
      insert(:staff, role: insert(:role, permissions: ~w(marketing.read marketing.manage)))

    insert(:staff_branch, staff: no_delete, branch: ctx.branch)
    no_delete = Repo.preload(no_delete, [:role, :branches])
    assert {:error, :forbidden} = Marketing.delete(no_delete, policy.id, policy.revision)
    assert {:error, :stale} = Marketing.delete(ctx.staff, policy.id, policy.revision + 1)
    assert {:ok, _} = Features.configure("marketing_policies", :franchise, false, actor: "test")
    assert {:error, :not_found} = Marketing.delete(ctx.staff, policy.id, policy.revision)
    assert Repo.get(Policy, policy.id)
  end

  defp create_policy(ctx, mode \\ "all_current") do
    {:ok, segment} =
      Segments.create(ctx.staff, %{name: "Lifecycle audience", kind: :manual, scope: :branches}, [
        ctx.branch.id
      ])

    {:ok, policy} = Marketing.create(ctx.staff, attrs(ctx, segment, mode), [ctx.branch.id])
    policy
  end

  defp attrs(_ctx, %Policy{} = policy) do
    %{
      "name" => policy.name,
      "scope" => Atom.to_string(policy.scope),
      "segment_id" => policy.segment_id,
      "reward_branch_id" => policy.reward_branch_id,
      "promotion_id" => policy.promotion_id,
      "bonus_amount" => policy.bonus_amount,
      "inactivity_days" => policy.inactivity_days,
      "reward_ttl_days" => policy.reward_ttl_days,
      "attribution_days" => policy.attribution_days,
      "initial_mode" => Atom.to_string(policy.initial_mode),
      "channels" => policy.channels,
      "message_title" => policy.message_title,
      "message_body" => policy.message_body,
      "max_issues" => policy.max_issues,
      "expected_revision" => policy.revision
    }
  end

  defp attrs(ctx, segment, mode) do
    %{
      "name" => "Lifecycle offer",
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
      OrderFixtures.order_fixture(ctx.branch.id, attrs: %{"customer_phone" => ctx.client.phone})

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
end
