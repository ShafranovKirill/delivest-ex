defmodule Delivest.MarketingRaceTest do
  use ExUnit.Case, async: false
  import Delivest.Factory
  import Ecto.Query

  alias Delivest.{Features, Marketing, Repo}
  alias Delivest.Background.Schedule
  alias Delivest.Marketing.{Issue, Policy}
  alias Delivest.Oms.{Cart, Order, OrderTransition}
  alias Delivest.Promo.PromoCode
  alias Delivest.Segments.Segment

  setup do
    fixture =
      unboxed(fn ->
        branch = insert(:branch, is_active: true)
        client = insert(:client)
        {:ok, _} = Features.configure("marketing_policies", :franchise, true, actor: "race")

        {:ok, _} =
          Features.configure("marketing_policies", {:branch, branch.id}, true, actor: "race")

        promotion = insert_promotion(branch.id, kind: :personal_code, rules: "then discount 10%")
        segment = Repo.insert!(%Segment{name: "Race audience", kind: :manual, scope: :branches})

        Repo.insert_all("segment_manual_members", [
          %{
            segment_id: Ecto.UUID.dump!(segment.id),
            client_id: Ecto.UUID.dump!(client.id),
            inserted_at: NaiveDateTime.utc_now(:second),
            updated_at: NaiveDateTime.utc_now(:second)
          }
        ])

        {order, cart} = order(branch.id, client.id, :completed, 31)
        {fresh, fresh_cart} = order(branch.id, client.id, :created, 0)

        policy =
          Repo.insert!(%Policy{
            name: "Race policy",
            segment_id: segment.id,
            scope: :branches,
            reward_branch_id: branch.id,
            promotion_id: promotion.id,
            inactivity_days: 30,
            reward_ttl_days: 14,
            attribution_days: 7,
            status: :active,
            message_title: "Return",
            message_body: "Offer"
          })

        Repo.insert_all("marketing_policy_branches", [
          %{
            policy_id: Ecto.UUID.dump!(policy.id),
            branch_id: Ecto.UUID.dump!(branch.id)
          }
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
          order: order,
          cart: cart,
          fresh: fresh,
          fresh_cart: fresh_cart,
          promotion: promotion,
          segment: segment,
          job: job,
          policy: policy,
          context: context
        }
      end)

    on_exit(fn ->
      unboxed(fn ->
        Repo.delete_all(
          from n in Delivest.Notifications.Notification,
            where: n.branch_id == ^fixture.branch.id
        )

        Repo.delete_all(from c in PromoCode, where: c.promotion_id == ^fixture.promotion.id)
        Repo.delete_all(from i in Issue, where: i.policy_id == ^fixture.policy.id)

        Repo.delete_all(
          from t in OrderTransition,
            where: t.order_id in ^[fixture.order.id, fixture.fresh.id]
        )

        Repo.delete!(fixture.order)
        Repo.delete!(fixture.fresh)
        Repo.delete!(fixture.cart)
        Repo.delete!(fixture.fresh_cart)

        Repo.delete_all(
          from b in "marketing_policy_branches",
            where: b.policy_id == type(^fixture.policy.id, :binary_id)
        )

        Repo.delete!(fixture.policy)

        Repo.delete_all(
          from m in "segment_manual_members",
            where: m.segment_id == type(^fixture.segment.id, :binary_id)
        )

        Repo.delete!(fixture.segment)
        Repo.delete!(fixture.promotion)
        Repo.delete_all(from j in Oban.Job, where: j.id == ^fixture.job.id)

        Repo.delete_all(
          from s in Schedule,
            where: s.scope_key == ^("branch:" <> fixture.branch.id)
        )

        Repo.delete_all(
          from g in Delivest.Features.Gate,
            where: g.scope_key == ^("branch:" <> fixture.branch.id)
        )

        Repo.delete!(fixture.client)
        Repo.delete!(fixture.branch)

        {:ok, _} =
          Features.configure("marketing_policies", :franchise, false, actor: "race-cleanup")

        {:ok, _} = Features.configure("segments", :franchise, false, actor: "race-cleanup")
        {:ok, _} = Features.configure("notifications", :franchise, false, actor: "race-cleanup")
      end)
    end)

    {:ok, fixture}
  end

  test "two independent connections grant exactly one issue, code and notice", ctx do
    tasks =
      for _ <- 1..2,
          do:
            Task.async(fn ->
              unboxed(fn -> Marketing.issue(ctx.policy, ctx.client.id, ctx.context) end)
            end)

    results = Enum.map(tasks, &Task.await(&1, 10_000))
    assert Enum.count(results, &match?({:ok, %Issue{}}, &1)) == 1
    assert Enum.count(results, &(&1 in [{:ok, :skipped}, {:error, :already_issued}])) == 1

    unboxed(fn ->
      assert Repo.aggregate(from(i in Issue, where: i.policy_id == ^ctx.policy.id), :count) == 1

      assert Repo.aggregate(
               from(c in PromoCode, where: c.promotion_id == ^ctx.policy.promotion_id),
               :count
             ) == 1

      assert Repo.aggregate(
               from(n in Delivest.Notifications.Notification,
                 where: n.client_id == ^ctx.client.id
               ),
               :count
             ) == 1
    end)
  end

  test "completed order wins client lock before reward grant", ctx do
    fresh = ctx.fresh
    parent = self()

    completing =
      Task.async(fn ->
        unboxed(fn ->
          Repo.transaction(fn ->
            Marketing.lock_completion(ctx.client.id, ctx.branch.id)
            send(parent, {:completion_locked, self()})

            receive do
              :release_completion -> :ok
            after
              5_000 -> raise "completion barrier timed out"
            end

            Repo.update_all(from(o in Order, where: o.id == ^fresh.id), set: [status: :completed])

            Repo.insert!(%OrderTransition{
              order_id: fresh.id,
              from: :created,
              to: :completed,
              source: :staff,
              inserted_at: DateTime.utc_now(:microsecond)
            })
          end)
        end)
      end)

    assert_receive {:completion_locked, completion_pid}

    granting =
      Task.async(fn ->
        send(parent, :grant_started)
        unboxed(fn -> Marketing.issue(ctx.policy, ctx.client.id, ctx.context) end)
      end)

    assert_receive :grant_started
    assert Task.yield(granting, 100) == nil

    unboxed(fn ->
      refute Repo.exists?(from i in Issue, where: i.policy_id == ^ctx.policy.id)
    end)

    send(completion_pid, :release_completion)
    assert {:ok, _} = Task.await(completing, 10_000)
    assert {:ok, :skipped} = Task.await(granting, 10_000)

    unboxed(fn ->
      refute Repo.exists?(from i in Issue, where: i.policy_id == ^ctx.policy.id)
    end)
  end

  defp order(branch_id, client_id, status, days_ago) do
    cart = Repo.insert!(%Cart{branch_id: branch_id, client_id: client_id})

    order =
      Repo.insert!(%Order{
        branch_id: branch_id,
        client_id: client_id,
        cart_id: cart.id,
        number: "R-#{Ecto.UUID.generate()}",
        daily_number: :erlang.unique_integer([:positive]),
        business_date: Date.utc_today(),
        status: status,
        total_amount: 100
      })

    if status == :completed do
      Repo.insert!(%OrderTransition{
        order_id: order.id,
        from: :created,
        to: :completed,
        source: :staff,
        inserted_at: DateTime.add(DateTime.utc_now(:microsecond), -days_ago * 86_400, :second)
      })
    end

    {order, cart}
  end

  defp unboxed(fun), do: Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fun)
end
