defmodule Delivest.MarketingPushReservationConcurrencyTest do
  use ExUnit.Case, async: false
  import Delivest.Factory
  import Ecto.Query

  alias Delivest.Notifications.{
    Intent,
    MarketingPushLimiter,
    MarketingPushReservation,
    Notification
  }

  alias Delivest.Repo
  alias Ecto.Adapters.SQL.Sandbox

  test "two independent connections cannot reserve above the client budget" do
    {branch, client, first, second} =
      Sandbox.unboxed_run(Repo, fn ->
        branch = insert(:branch)
        client = insert(:client)
        {branch, client, intent(client, branch), intent(client, branch)}
      end)

    parent = self()
    supervisor = start_supervised!(Task.Supervisor)

    first_task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Repo.transaction(fn ->
            result = MarketingPushLimiter.claim(first.id, client.id)
            send(parent, {:first_claimed, result})

            receive do
              :release -> :ok
            after
              5_000 -> raise "first transaction was not released"
            end

            result
          end)
        end)
      end)

    second_task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        receive do
          :start -> :ok
        end

        Sandbox.unboxed_run(Repo, fn ->
          Repo.transaction(fn ->
            send(parent, :second_started)
            MarketingPushLimiter.claim(second.id, client.id)
          end)
        end)
      end)

    try do
      assert_receive {:first_claimed, :reserved}, 5_000
      send(second_task.pid, :start)
      assert_receive :second_started, 5_000
      send(first_task.pid, :release)
      assert {:ok, :reserved} = Task.await(first_task, 10_000)
      assert {:ok, :limited} = Task.await(second_task, 10_000)

      Sandbox.unboxed_run(Repo, fn ->
        assert Repo.aggregate(MarketingPushReservation, :count) == 1
      end)
    after
      send(first_task.pid, :release)
      Task.Supervisor.terminate_child(supervisor, first_task.pid)
      Task.Supervisor.terminate_child(supervisor, second_task.pid)

      Sandbox.unboxed_run(Repo, fn ->
        Repo.delete_all(from n in Notification, where: n.client_id == ^client.id)
        Repo.delete!(client)
        Repo.delete!(branch)
      end)
    end
  end

  defp intent(client, branch) do
    notice =
      Repo.insert!(%Notification{
        client_id: client.id,
        branch_id: branch.id,
        idempotency_key: Ecto.UUID.generate(),
        source_type: "marketing_reward",
        source_id: Ecto.UUID.generate(),
        source_feature: "marketing_policies",
        source_scope_key: "branch:" <> branch.id,
        source_generation_franchise: 1,
        source_generation_branch: 1,
        notification_generation_franchise: 1,
        notification_generation_branch: 1,
        title: "Offer",
        body: "Text"
      })

    Repo.insert!(%Intent{
      notification_id: notice.id,
      channel: "push",
      due_at: DateTime.utc_now(:microsecond)
    })
  end
end
