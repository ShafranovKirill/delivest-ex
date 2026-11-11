defmodule Delivest.NotificationsConcurrencyTest do
  use ExUnit.Case, async: false
  import Delivest.Factory
  import Ecto.Query
  alias Delivest.{Features, Notifications, Repo}
  alias Delivest.Notifications.Intent
  alias Delivest.Background.Schedule
  alias Delivest.Marketing.{Issue, Policy}
  alias Delivest.Oms.{Cart, Order}
  alias Delivest.Segments.Segment
  alias Ecto.Adapters.SQL.Sandbox

  test "independent connections publish one notice and one intent for the same key" do
    {branch, client, source_id, issue, order, cart, policy, segment} =
      Sandbox.unboxed_run(Repo, fn ->
        branch = insert(:branch)
        client = insert(:client)
        {:ok, _} = Features.configure("notifications", :franchise, true, actor: "race")
        {:ok, _} = Features.configure("notifications", {:branch, branch.id}, true, actor: "race")
        {:ok, _} = Features.configure("marketing_policies", :franchise, true, actor: "race")

        {:ok, _} =
          Features.configure("marketing_policies", {:branch, branch.id}, true, actor: "race")

        {:ok, generation} = Features.snapshot("marketing_policies", {:branch, branch.id})
        segment = Repo.insert!(%Segment{name: "Race", kind: :manual, scope: :branches})

        policy =
          Repo.insert!(%Policy{
            name: "Race",
            segment_id: segment.id,
            scope: :branches,
            reward_branch_id: branch.id,
            bonus_amount: 1,
            inactivity_days: 1,
            reward_ttl_days: 1,
            attribution_days: 1,
            status: :active,
            message_title: "Offer",
            message_body: "Text"
          })

        cart = Repo.insert!(%Cart{branch_id: branch.id, client_id: client.id})

        order =
          Repo.insert!(%Order{
            branch_id: branch.id,
            client_id: client.id,
            cart_id: cart.id,
            number: "R-#{Ecto.UUID.generate()}",
            daily_number: :erlang.unique_integer([:positive]),
            business_date: Date.utc_today(),
            status: :completed,
            total_amount: 100
          })

        now = DateTime.utc_now(:second)

        issue =
          Repo.insert!(%Issue{
            policy_id: policy.id,
            client_id: client.id,
            cycle_order_id: order.id,
            branch_id: branch.id,
            reward_type: "bonus",
            reward_amount: 1,
            issued_at: now,
            expires_at: DateTime.add(now, 86_400, :second),
            attribution_until: DateTime.add(now, 86_400, :second),
            policy_revision: 1,
            source_generation_franchise: generation.franchise,
            source_generation_branch: generation.branch
          })

        {branch, client, issue.id, issue, order, cart, policy, segment}
      end)

    try do
      opts = [
        idempotency_key: source_id,
        source_type: "marketing_reward",
        source_id: source_id,
        branch_id: branch.id,
        channels: [:in_app]
      ]

      tasks =
        for _ <- 1..2 do
          Task.async(fn ->
            receive do
              :publish -> :ok
            end

            Sandbox.unboxed_run(Repo, fn ->
              Notifications.publish(client.id, %{title: "Offer", body: "Text"}, opts)
            end)
          end)
        end

      Enum.each(tasks, &send(&1.pid, :publish))
      assert [{:ok, first}, {:ok, second}] = Task.await_many(tasks, 10_000)
      assert first.id == second.id

      Sandbox.unboxed_run(Repo, fn ->
        assert Repo.aggregate(
                 from(n in Delivest.Notifications.Notification,
                   where: n.idempotency_key == ^source_id
                 ),
                 :count
               ) == 1

        assert Repo.aggregate(from(i in Intent, where: i.notification_id == ^first.id), :count) ==
                 1
      end)
    after
      Sandbox.unboxed_run(Repo, fn ->
        Repo.delete_all(
          from n in Delivest.Notifications.Notification, where: n.branch_id == ^branch.id
        )

        Repo.delete!(issue)
        Repo.delete!(order)
        Repo.delete!(cart)
        Repo.delete!(policy)
        Repo.delete!(segment)

        Repo.delete_all(from s in Schedule, where: s.scope_key == ^("branch:" <> branch.id))

        Repo.delete_all(
          from g in Delivest.Features.Gate, where: g.scope_key == ^("branch:" <> branch.id)
        )

        Repo.delete!(client)
        Repo.delete!(branch)

        {:ok, _} =
          Features.configure("marketing_policies", :franchise, false, actor: "race-cleanup")

        {:ok, _} = Features.configure("segments", :franchise, false, actor: "race-cleanup")
        {:ok, _} = Features.configure("notifications", :franchise, false, actor: "race-cleanup")
      end)
    end
  end
end
