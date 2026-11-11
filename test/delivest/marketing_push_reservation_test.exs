defmodule Delivest.MarketingPushReservationTest do
  use Delivest.DataCase, async: false
  import Delivest.Factory
  import Ecto.Query

  alias Delivest.Franchise.Settings

  alias Delivest.Notifications.{
    Intent,
    MarketingPushLimiter,
    MarketingPushReservation,
    Notification
  }

  alias Delivest.Repo

  setup do
    %{branch: insert(:branch), client: insert(:client)}
  end

  test "default budget is shared by intents and branches for one client", context do
    first = intent(context.client, context.branch)
    second = intent(context.client, insert(:branch))
    other_client = insert(:client)
    other = intent(other_client, context.branch)

    assert :reserved = MarketingPushLimiter.claim(first.id, context.client.id)
    assert :reserved = MarketingPushLimiter.claim(first.id, context.client.id)
    assert :limited = MarketingPushLimiter.claim(second.id, context.client.id)
    assert :reserved = MarketingPushLimiter.claim(other.id, other_client.id)
    assert Repo.aggregate(MarketingPushReservation, :count) == 2
  end

  test "rolling boundary and an old intent cannot be reserved twice", context do
    first = intent(context.client, context.branch)
    second = intent(context.client, context.branch)
    assert :reserved = MarketingPushLimiter.claim(first.id, context.client.id)

    Repo.update_all(
      from(r in MarketingPushReservation, where: r.intent_id == ^first.id),
      set: [reserved_at: DateTime.add(DateTime.utc_now(:microsecond), -86_400, :second)]
    )

    assert :stale = MarketingPushLimiter.claim(first.id, context.client.id)
    assert :reserved = MarketingPushLimiter.claim(second.id, context.client.id)
  end

  test "configured count and window are read from the database on claim", context do
    settings = Repo.one!(Settings)

    Repo.update!(
      Settings.changeset(settings, %{
        marketing_push_limit_count: 2,
        marketing_push_window_hours: 1
      })
    )

    first = intent(context.client, context.branch)
    second = intent(context.client, context.branch)
    third = intent(context.client, context.branch)
    assert :reserved = MarketingPushLimiter.claim(first.id, context.client.id)
    assert :reserved = MarketingPushLimiter.claim(second.id, context.client.id)
    assert :limited = MarketingPushLimiter.claim(third.id, context.client.id)

    Repo.update_all(
      from(r in MarketingPushReservation, where: r.intent_id == ^first.id),
      set: [reserved_at: DateTime.add(DateTime.utc_now(:microsecond), -3_600, :second)]
    )

    assert :reserved = MarketingPushLimiter.claim(third.id, context.client.id)
    assert :stale = MarketingPushLimiter.claim(first.id, context.client.id)
  end

  test "an existing intent cannot be claimed as another client's Push", context do
    first = intent(context.client, context.branch)
    assert :reserved = MarketingPushLimiter.claim(first.id, context.client.id)

    assert_raise ArgumentError, ~r/another client/, fn ->
      MarketingPushLimiter.claim(first.id, insert(:client).id)
    end
  end

  defp intent(client, branch) do
    notification =
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
      notification_id: notification.id,
      channel: "push",
      due_at: DateTime.utc_now(:microsecond)
    })
  end
end
