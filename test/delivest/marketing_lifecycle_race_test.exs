defmodule Delivest.MarketingLifecycleRaceTest do
  use ExUnit.Case, async: false
  import Delivest.Factory
  import Ecto.Query

  alias Delivest.{Features, Marketing, Repo}
  alias Delivest.Background.Schedule
  alias Delivest.Marketing.{Issue, Policy}
  alias Delivest.Oms.{Cart, Order, OrderTransition}
  alias Delivest.Segments.Segment

  setup do
    fixture =
      unboxed(fn ->
        baseline_schedule_ids =
          Repo.all(from s in Schedule, where: s.scope_key == "franchise", select: s.id)

        assert baseline_schedule_ids == []

        refute Repo.exists?(
                 from g in Delivest.Features.Gate,
                   where:
                     g.scope_key == "franchise" and g.enabled == true and
                       g.feature in ["marketing_policies", "segments", "notifications"]
               )

        branch = insert(:branch, is_active: true)
        client = insert(:client)

        staff =
          insert(:staff, role: insert(:role, permissions: ~w(marketing.read marketing.delete)))

        insert(:staff_branch, staff: staff, branch: branch)
        staff = Repo.preload(staff, [:role, :branches])
        {:ok, _} = Features.configure("marketing_policies", :franchise, true, actor: "race")

        {:ok, _} =
          Features.configure("marketing_policies", {:branch, branch.id}, true, actor: "race")

        promotion = insert_promotion(branch.id, kind: :personal_code, rules: "then discount 10%")
        segment = Repo.insert!(%Segment{name: "Delete race", kind: :manual, scope: :branches})

        Repo.insert_all("segment_manual_members", [
          %{
            segment_id: Ecto.UUID.dump!(segment.id),
            client_id: Ecto.UUID.dump!(client.id),
            inserted_at: NaiveDateTime.utc_now(:second),
            updated_at: NaiveDateTime.utc_now(:second)
          }
        ])

        cart = Repo.insert!(%Cart{branch_id: branch.id, client_id: client.id})

        order =
          Repo.insert!(%Order{
            branch_id: branch.id,
            client_id: client.id,
            cart_id: cart.id,
            number: "D-#{Ecto.UUID.generate()}",
            daily_number: :erlang.unique_integer([:positive]),
            business_date: Date.utc_today(),
            status: :completed,
            total_amount: 100
          })

        Repo.insert!(%OrderTransition{
          order_id: order.id,
          from: :created,
          to: :completed,
          source: :staff,
          inserted_at: DateTime.add(DateTime.utc_now(:microsecond), -31 * 86_400, :second)
        })

        policy =
          Repo.insert!(%Policy{
            name: "Delete race policy",
            segment_id: segment.id,
            scope: :branches,
            reward_branch_id: branch.id,
            promotion_id: promotion.id,
            inactivity_days: 30,
            reward_ttl_days: 14,
            attribution_days: 7,
            status: :active,
            activated_at: DateTime.utc_now(:second),
            message_title: "Return",
            message_body: "Offer"
          })

        Repo.insert_all("marketing_policy_branches", [
          %{policy_id: Ecto.UUID.dump!(policy.id), branch_id: Ecto.UUID.dump!(branch.id)}
        ])

        {:ok, generation} = Features.snapshot("marketing_policies", :franchise)
        schedule = Repo.get_by!(Schedule, kind: "marketing.evaluate", scope_key: "franchise")

        job =
          Repo.insert!(%Oban.Job{
            worker: "Delivest.Background.Runner",
            queue: "background",
            args: %{"kind" => "marketing.evaluate"},
            state: "executing",
            max_attempts: 1
          })

        Repo.update!(Ecto.Changeset.change(schedule, running: true, current_job_id: job.id))

        context = %{
          feature: "marketing_policies",
          scope: :franchise,
          generation: generation,
          schedule_id: schedule.id,
          job_id: job.id
        }

        %{
          branch: branch,
          client: client,
          staff: staff,
          promotion: promotion,
          segment: segment,
          cart: cart,
          order: order,
          policy: policy,
          job: job,
          schedule: schedule,
          baseline_schedule_ids: baseline_schedule_ids,
          context: context
        }
      end)

    on_exit(fn ->
      unboxed(fn ->
        Repo.delete_all(
          from n in Delivest.Notifications.Notification, where: n.client_id == ^fixture.client.id
        )

        Repo.delete_all(
          from c in Delivest.Promo.PromoCode, where: c.promotion_id == ^fixture.promotion.id
        )

        Repo.delete_all(from i in Issue, where: i.policy_id == ^fixture.policy.id)

        Repo.delete_all(
          from a in "marketing_policy_audits",
            where: a.policy_id == type(^fixture.policy.id, :binary_id)
        )

        Repo.delete_all(
          from a in Delivest.Audit.Event,
            where:
              a.action == "marketing.policy_deleted" and
                fragment("?->>'policy_id'", a.metadata) == ^fixture.policy.id
        )

        Repo.delete_all(
          from b in "marketing_policy_branches",
            where: b.policy_id == type(^fixture.policy.id, :binary_id)
        )

        Repo.delete_all(from p in Policy, where: p.id == ^fixture.policy.id)

        Repo.delete_all(
          from m in "segment_manual_members",
            where: m.segment_id == type(^fixture.segment.id, :binary_id)
        )

        Repo.delete!(fixture.segment)
        Repo.delete!(fixture.promotion)
        Repo.delete_all(from t in OrderTransition, where: t.order_id == ^fixture.order.id)
        Repo.delete!(fixture.order)
        Repo.delete!(fixture.cart)
        Repo.delete_all(from j in Oban.Job, where: j.id == ^fixture.job.id)

        Repo.delete_all(
          from s in Schedule, where: s.scope_key == ^("branch:" <> fixture.branch.id)
        )

        Repo.delete_all(
          from g in Delivest.Features.Gate,
            where: g.scope_key == ^("branch:" <> fixture.branch.id)
        )

        Repo.delete_all(
          from sb in Delivest.Identity.StaffBranch, where: sb.staff_id == ^fixture.staff.id
        )

        Repo.delete!(fixture.staff)
        Repo.delete!(fixture.staff.role)
        Repo.delete!(fixture.client)
        Repo.delete!(fixture.branch)

        {:ok, _} =
          Features.configure("marketing_policies", :franchise, false, actor: "race-cleanup")

        {:ok, _} = Features.configure("segments", :franchise, false, actor: "race-cleanup")
        {:ok, _} = Features.configure("notifications", :franchise, false, actor: "race-cleanup")

        refute Repo.exists?(from s in Schedule, where: s.id == ^fixture.schedule.id)

        assert Repo.all(from s in Schedule, where: s.scope_key == "franchise", select: s.id)
               |> Enum.sort() ==
                 fixture.baseline_schedule_ids
      end)
    end)

    {:ok, fixture}
  end

  test "deletion serializes before a queued issue", ctx do
    parent = self()

    holder =
      Task.async(fn ->
        unboxed(fn ->
          Repo.transaction(fn ->
            Repo.one!(from p in Policy, where: p.id == ^ctx.policy.id, lock: "FOR UPDATE")
            [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
            send(parent, {:locked, self(), backend_pid})

            receive do
              :release -> :ok
            after
              5_000 -> raise "policy lock barrier timed out"
            end
          end)
        end)
      end)

    assert_receive {:locked, holder_pid, holder_backend_pid}
    on_exit(fn -> send(holder_pid, :release) end)

    deleting =
      Task.async(fn ->
        unboxed(fn ->
          on_connection(parent, :delete_started, fn ->
            Marketing.delete(ctx.staff, ctx.policy.id, ctx.policy.revision)
          end)
        end)
      end)

    assert_receive {:delete_started, deleting_backend_pid}
    refute deleting_backend_pid == holder_backend_pid
    await_blocked(deleting_backend_pid)

    issuing =
      Task.async(fn ->
        unboxed(fn ->
          on_connection(parent, :issue_started, fn ->
            Marketing.issue(ctx.policy, ctx.client.id, ctx.context)
          end)
        end)
      end)

    assert_receive {:issue_started, issuing_backend_pid}
    refute issuing_backend_pid in [holder_backend_pid, deleting_backend_pid]
    await_blocked(issuing_backend_pid)
    send(holder_pid, :release)
    assert {:ok, _} = Task.await(holder, 10_000)
    assert {:ok, :archived} = Task.await(deleting, 10_000)
    assert {:error, :stale} = Task.await(issuing, 10_000)

    unboxed(fn ->
      refute Repo.exists?(from i in Issue, where: i.policy_id == ^ctx.policy.id)
    end)
  end

  test "hard deletion prevents a queued report request from recreating policy data", ctx do
    policy =
      unboxed(fn ->
        Repo.update!(Ecto.Changeset.change(ctx.policy, status: :draft, activated_at: nil))
      end)

    parent = self()

    holder =
      Task.async(fn ->
        unboxed(fn ->
          Repo.transaction(fn ->
            Repo.one!(from p in Policy, where: p.id == ^policy.id, lock: "FOR UPDATE")
            [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
            send(parent, {:locked, self(), backend_pid})

            receive do
              :release -> :ok
            after
              5_000 -> raise "policy lock barrier timed out"
            end
          end)
        end)
      end)

    assert_receive {:locked, holder_pid, holder_backend_pid}
    on_exit(fn -> send(holder_pid, :release) end)

    deleting =
      Task.async(fn ->
        unboxed(fn ->
          on_connection(parent, :delete_started, fn ->
            Marketing.delete(ctx.staff, policy.id, policy.revision)
          end)
        end)
      end)

    assert_receive {:delete_started, deleting_backend_pid}
    refute deleting_backend_pid == holder_backend_pid
    await_blocked(deleting_backend_pid)

    reporting =
      Task.async(fn ->
        unboxed(fn ->
          on_connection(parent, :report_started, fn ->
            Delivest.Marketing.Report.request(policy)
          end)
        end)
      end)

    assert_receive {:report_started, reporting_backend_pid}
    refute reporting_backend_pid in [holder_backend_pid, deleting_backend_pid]
    await_blocked(reporting_backend_pid)
    send(holder_pid, :release)

    assert {:ok, _} = Task.await(holder, 10_000)
    assert {:ok, :deleted} = Task.await(deleting, 10_000)
    assert {:error, :stale} = Task.await(reporting, 10_000)

    unboxed(fn ->
      refute Repo.exists?(
               from r in "marketing_report_requests",
                 where: r.policy_id == type(^policy.id, :binary_id)
             )
    end)
  end

  test "preview worker finishes when a pending preview is hard deleted", ctx do
    {policy, preview_context} =
      unboxed(fn ->
        policy =
          Repo.update!(Ecto.Changeset.change(ctx.policy, status: :draft, activated_at: nil))

        Repo.insert_all("marketing_previews", [
          %{
            policy_id: Ecto.UUID.dump!(policy.id),
            policy_revision: policy.revision,
            segment_revision: ctx.segment.revision,
            feature_generation: ctx.context.generation.franchise,
            request_id: Ecto.UUID.generate() |> Ecto.UUID.dump!(),
            status: "pending",
            requested_at: DateTime.utc_now(:second)
          }
        ])

        schedule = Repo.get_by!(Schedule, kind: "marketing.preview", scope_key: "franchise")
        Repo.update!(Ecto.Changeset.change(schedule, running: true, current_job_id: ctx.job.id))
        {policy, %{ctx.context | schedule_id: schedule.id}}
      end)

    parent = self()

    holder =
      Task.async(fn ->
        unboxed(fn ->
          Repo.transaction(fn ->
            Repo.one!(from p in Policy, where: p.id == ^policy.id, lock: "FOR UPDATE")
            [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
            send(parent, {:locked, self(), backend_pid})

            receive do
              :release -> :ok
            after
              5_000 -> raise "policy lock barrier timed out"
            end
          end)
        end)
      end)

    assert_receive {:locked, holder_pid, holder_backend_pid}
    on_exit(fn -> send(holder_pid, :release) end)

    deleting =
      Task.async(fn ->
        unboxed(fn ->
          on_connection(parent, :delete_started, fn ->
            Marketing.delete(ctx.staff, policy.id, policy.revision)
          end)
        end)
      end)

    assert_receive {:delete_started, deleting_backend_pid}
    refute deleting_backend_pid == holder_backend_pid
    await_blocked(deleting_backend_pid)

    previewing =
      Task.async(fn ->
        unboxed(fn ->
          on_connection(parent, :preview_started, fn ->
            Delivest.Marketing.Preview.perform(:franchise, preview_context)
          end)
        end)
      end)

    assert_receive {:preview_started, preview_backend_pid}
    refute preview_backend_pid in [holder_backend_pid, deleting_backend_pid]
    await_blocked(preview_backend_pid)
    send(holder_pid, :release)

    assert {:ok, _} = Task.await(holder, 10_000)
    assert {:ok, :deleted} = Task.await(deleting, 10_000)
    assert :ok = Task.await(previewing, 10_000)

    unboxed(fn ->
      refute Repo.exists?(
               from p in "marketing_previews", where: p.policy_id == type(^policy.id, :binary_id)
             )

      refute Repo.exists?(
               from l in "segment_snapshot_leases",
                 where:
                   l.owner_type == "marketing_preview" and
                     l.owner_id == type(^policy.id, :binary_id)
             )
    end)
  end

  test "report worker finishes when its pending request is hard deleted", ctx do
    {policy, report_context, request_id} =
      unboxed(fn ->
        policy =
          Repo.update!(Ecto.Changeset.change(ctx.policy, status: :draft, activated_at: nil))

        request_id = Ecto.UUID.generate()
        now = DateTime.utc_now(:microsecond)

        Repo.insert_all("marketing_report_requests", [
          %{
            id: Ecto.UUID.dump!(request_id),
            policy_id: Ecto.UUID.dump!(policy.id),
            from_on: Date.add(Date.utc_today(), -30),
            to_on: Date.utc_today(),
            branch_key: "all",
            status: "pending",
            phase: "issues",
            requested_at: now,
            updated_at: now
          }
        ])

        schedule = Repo.get_by!(Schedule, kind: "marketing.report", scope_key: "franchise")
        Repo.update!(Ecto.Changeset.change(schedule, running: true, current_job_id: ctx.job.id))
        {policy, %{ctx.context | schedule_id: schedule.id}, request_id}
      end)

    parent = self()
    supervisor = start_supervised!({Task.Supervisor, []})

    holder =
      Task.Supervisor.async_nolink(supervisor, fn ->
        unboxed(fn ->
          Repo.transaction(fn ->
            Repo.one!(from p in Policy, where: p.id == ^policy.id, lock: "FOR UPDATE")
            [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
            send(parent, {:locked, self(), backend_pid})

            receive do
              :release -> :ok
            after
              5_000 -> raise "policy lock barrier timed out"
            end
          end)
        end)
      end)

    assert_receive {:locked, holder_pid, holder_backend_pid}

    on_exit(fn -> send(holder_pid, :release) end)

    deleting =
      Task.Supervisor.async_nolink(supervisor, fn ->
        unboxed(fn ->
          on_connection(parent, :delete_started, fn ->
            Marketing.delete(ctx.staff, policy.id, policy.revision)
          end)
        end)
      end)

    assert_receive {:delete_started, deleting_backend_pid}
    refute deleting_backend_pid == holder_backend_pid
    await_blocked(deleting_backend_pid)

    marker = make_ref()
    handler_id = "marketing-report-hard-delete-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:delivest, :repo, :query],
        fn _, _, metadata, {owner, ref} ->
          if Process.get(:report_delete_marker) == ref and
               String.contains?(
                 metadata.query,
                 "FROM marketing_report_requests WHERE status='pending'"
               ) do
            Process.delete(:report_delete_marker)
            send(owner, {:report_request_selected, self()})

            receive do
              {^ref, :continue} -> :ok
            after
              5_000 -> raise "report select barrier timed out"
            end
          end
        end,
        {parent, marker}
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    reporting =
      Task.Supervisor.async_nolink(supervisor, fn ->
        Process.put(:report_delete_marker, marker)

        unboxed(fn ->
          on_connection(parent, :report_worker_started, fn ->
            Delivest.Marketing.Report.perform(:franchise, report_context)
          end)
        end)
      end)

    try do
      assert_receive {:report_worker_started, reporting_backend_pid}
      refute reporting_backend_pid in [holder_backend_pid, deleting_backend_pid]
      assert_receive {:report_request_selected, reporting_pid}
      assert reporting_pid == reporting.pid
      send(holder_pid, :release)

      assert {:ok, _} = Task.await(holder, 10_000)
      assert {:ok, :deleted} = Task.await(deleting, 10_000)
      send(reporting_pid, {marker, :continue})
      assert :ok = Task.await(reporting, 10_000)

      unboxed(fn ->
        refute Repo.exists?(
                 from row in "marketing_report_requests",
                   where: row.id == type(^request_id, :binary_id)
               )

        for table <- ["marketing_report_links", "marketing_report_daily"] do
          refute Repo.exists?(
                   from row in table, where: row.request_id == type(^request_id, :binary_id)
                 )
        end
      end)
    after
      :telemetry.detach(handler_id)
      send(holder.pid, :release)
      send(reporting.pid, {marker, :continue})

      for task <- [reporting, deleting, holder],
          do: Task.Supervisor.terminate_child(supervisor, task.pid)
    end
  end

  test "preview selected just before hard deletion finishes without retry", ctx do
    {policy, preview_context} =
      unboxed(fn ->
        policy =
          Repo.update!(Ecto.Changeset.change(ctx.policy, status: :draft, activated_at: nil))

        Repo.insert_all("marketing_previews", [
          %{
            policy_id: Ecto.UUID.dump!(policy.id),
            policy_revision: policy.revision,
            segment_revision: ctx.segment.revision,
            feature_generation: ctx.context.generation.franchise,
            request_id: Ecto.UUID.generate() |> Ecto.UUID.dump!(),
            status: "pending",
            requested_at: DateTime.utc_now(:second)
          }
        ])

        schedule = Repo.get_by!(Schedule, kind: "marketing.preview", scope_key: "franchise")
        Repo.update!(Ecto.Changeset.change(schedule, running: true, current_job_id: ctx.job.id))
        {policy, %{ctx.context | schedule_id: schedule.id}}
      end)

    parent = self()
    marker = make_ref()
    handler_id = "marketing-preview-hard-delete-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:delivest, :repo, :query],
        fn _, _, metadata, {owner, ref} ->
          if Process.get(:preview_delete_marker) == ref and
               String.contains?(metadata.query, "FROM marketing_previews WHERE status='pending'") do
            send(owner, {:preview_selected, self()})

            receive do
              {^ref, :continue} -> :ok
            after
              5_000 -> raise "preview select barrier timed out"
            end
          end
        end,
        {parent, marker}
      )

    task =
      Task.async(fn ->
        Process.put(:preview_delete_marker, marker)
        unboxed(fn -> Delivest.Marketing.Preview.perform(:franchise, preview_context) end)
      end)

    try do
      assert_receive {:preview_selected, worker_pid}
      assert worker_pid == task.pid

      assert {:ok, :deleted} =
               unboxed(fn -> Marketing.delete(ctx.staff, policy.id, policy.revision) end)

      send(worker_pid, {marker, :continue})
      assert :ok = Task.await(task, 10_000)

      unboxed(fn ->
        refute Repo.exists?(
                 from p in "marketing_previews",
                   where: p.policy_id == type(^policy.id, :binary_id)
               )

        refute Repo.exists?(
                 from l in "segment_snapshot_leases",
                   where:
                     l.owner_type == "marketing_preview" and
                       l.owner_id == type(^policy.id, :binary_id)
               )
      end)
    after
      :telemetry.detach(handler_id)
      send(task.pid, {marker, :continue})
      Task.yield(task, 1_000) || Task.shutdown(task)
    end
  end

  defp on_connection(parent, tag, fun) do
    Repo.checkout(fn ->
      [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
      send(parent, {tag, backend_pid})
      fun.()
    end)
  end

  defp await_blocked(backend_pid, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 5_000

    blocked? =
      unboxed(fn ->
        [[blocking_pids]] = Repo.query!("SELECT pg_blocking_pids($1)", [backend_pid]).rows
        blocking_pids != []
      end)

    cond do
      blocked? ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("database backend was not blocked")

      true ->
        receive do
        after
          10 -> await_blocked(backend_pid, deadline)
        end
    end
  end

  defp unboxed(fun), do: Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fun)
end
