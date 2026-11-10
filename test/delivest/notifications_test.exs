defmodule Delivest.NotificationsTest do
  use Delivest.DataCase, async: false
  import Delivest.Factory
  import Ecto.Query

  alias Delivest.{Features, Notifications, Push, PushClient, Repo}
  alias Delivest.Notifications.{DeliverWorker, Intent}
  alias Delivest.Notifications.{Dispatch, PushDelivery, PushDeliveryWorker}
  alias Delivest.Background.Schedule
  alias Delivest.Marketing.{Issue, Policy}
  alias Delivest.Loyalty.Entry
  alias Delivest.Oms.{Cart, Order, OrderTransition}
  alias Delivest.Push.ClientSubscription
  alias Delivest.Segments.Segment

  setup do
    branch = insert(:branch)
    client = insert(:client)
    assert {:ok, _} = Features.configure("notifications", :franchise, true, actor: "test")

    assert {:ok, _} =
             Features.configure("notifications", {:branch, branch.id}, true, actor: "test")

    %{branch: branch, client: client}
  end

  test "idempotent publication writes durable intents and skips unconfigured channels", %{
    branch: branch,
    client: client
  } do
    source_id = active_source(branch, client)

    opts = [
      idempotency_key: source_id,
      source_type: "marketing_reward",
      source_id: source_id,
      branch_id: branch.id,
      channels: [:in_app, :push, :sms]
    ]

    attrs = %{title: "Offer", body: "Welcome", cta: %{type: "show_bonus", value: "bonus"}}

    assert {:ok, first} = Notifications.publish(client.id, attrs, opts)
    assert {:ok, second} = Notifications.publish(client.id, attrs, opts)
    assert first.id == second.id

    statuses =
      Repo.all(
        from i in Intent,
          where: i.notification_id == ^first.id,
          select: {i.channel, i.status, i.last_error}
      )
      |> Enum.sort()

    assert statuses == [
             {"in_app", "sent", nil},
             {"push", "skipped", "no_consent"},
             {"sms", "skipped", "provider_unconfigured"}
           ]
  end

  test "device dismissal is scoped to notice ownership and cannot cancel the reward", %{
    branch: branch,
    client: client
  } do
    source_id = active_source(branch, client)

    assert {:ok, notice} =
             Notifications.publish(client.id, %{title: "Offer", body: "Text"},
               idempotency_key: source_id,
               source_type: "marketing_reward",
               source_id: source_id,
               branch_id: branch.id,
               channels: [:in_app]
             )

    device_a = Ecto.UUID.generate()
    device_b = Ecto.UUID.generate()
    notice_id = notice.id

    assert {:ok, %{items: [%{id: ^notice_id}]}} =
             Notifications.list(client.id, branch.id, device_a)

    assert {:ok, %{items: [%{id: ^notice_id}]}} =
             Notifications.list(client.id, branch.id, device_b)

    assert :ok = Notifications.dismiss(client.id, branch.id, device_a, notice.id)
    assert :ok = Notifications.dismiss(client.id, branch.id, device_a, notice.id)

    assert {:error, :not_found} =
             Notifications.dismiss(insert(:client).id, branch.id, device_b, notice.id)

    assert {:error, :disabled} =
             Notifications.dismiss(client.id, insert(:branch).id, device_b, notice.id)

    assert {:ok, %{items: []}} = Notifications.list(client.id, branch.id, device_a)

    assert {:ok, %{items: [%{id: ^notice_id}]}} =
             Notifications.list(client.id, branch.id, device_b)

    assert {:ok, _} =
             Features.configure("marketing_policies", {:branch, branch.id}, false, actor: "test")

    assert {:ok, %{items: []}} = Notifications.list(client.id, branch.id, device_b)

    assert {:ok, _} =
             Features.configure("marketing_policies", {:branch, branch.id}, true, actor: "test")

    assert {:ok, %{items: [%{id: ^notice_id}]}} =
             Notifications.list(client.id, branch.id, device_b)

    issue = Repo.get!(Issue, source_id)

    Repo.update!(
      Ecto.Changeset.change(issue,
        expires_at: DateTime.add(DateTime.utc_now(:second), -1, :second)
      )
    )

    assert {:ok, %{items: []}} = Notifications.list(client.id, branch.id, device_b)
    assert {:error, :not_found} = Notifications.click(client.id, branch.id, device_b, notice.id)

    assert Repo.query!(
             "SELECT count(*) FROM customer_notification_dismissals WHERE notification_id=$1",
             [Ecto.UUID.dump!(notice.id)]
           ).rows == [[1]]

    assert Repo.get!(Delivest.Notifications.Notification, notice.id)
  end

  test "marketing opt-ins default off and feature disable blocks publication", %{
    branch: branch,
    client: client
  } do
    source_id = active_source(branch, client)
    assert {:ok, %{sms: false, push: false}} = Notifications.consents(client.id, branch.id)

    assert {:error, :invalid_consents} =
             Notifications.update_consents(client.id, branch.id, %{"sms" => true})

    assert {:ok, %{push: true}} =
             Notifications.update_consents(client.id, branch.id, %{"push" => true})

    assert {:ok, %{push: false}} =
             Notifications.update_consents(client.id, branch.id, %{"push" => false})

    assert Repo.query!(
             "SELECT old_value, new_value FROM customer_notification_consent_events WHERE client_id=$1 ORDER BY inserted_at, id",
             [Ecto.UUID.dump!(client.id)]
           ).rows == [[false, true], [true, false]]

    assert {:ok, preview} = Features.disable_preview("notifications", {:branch, branch.id})

    assert {:ok, _} =
             Features.configure("notifications", {:branch, branch.id}, false,
               actor: "test",
               confirm_dependents: preview
             )

    assert {:error, :disabled} =
             Notifications.publish(client.id, %{title: "Offer", body: "Text"},
               idempotency_key: Ecto.UUID.generate(),
               source_type: "marketing_reward",
               source_id: source_id,
               branch_id: branch.id,
               channels: [:in_app]
             )
  end

  test "a push-only notice has no site card, and stale raw pages retain a cursor", %{
    branch: branch,
    client: client
  } do
    device = Ecto.UUID.generate()
    source_id = active_source(branch, client)

    for index <- 1..32 do
      channels = if index == 1, do: [:push], else: [:in_app]

      assert {:ok, _} =
               Notifications.publish(client.id, %{title: "Offer", body: "Text"},
                 idempotency_key: Ecto.UUID.generate(),
                 source_type: "marketing_reward",
                 source_id: source_id,
                 branch_id: branch.id,
                 channels: channels
               )
    end

    issue = Repo.get!(Issue, source_id)

    Repo.update!(
      Ecto.Changeset.change(issue,
        expires_at: DateTime.add(DateTime.utc_now(:second), -1, :second)
      )
    )

    assert {:ok, %{items: [], next_cursor: cursor}} =
             Notifications.list(client.id, branch.id, device)

    assert is_binary(cursor)

    assert {:ok, %{items: [], next_cursor: nil}} =
             Notifications.list(client.id, branch.id, device, cursor)
  end

  test "queued delivery uses its job owner and a disabled generation cannot send", %{
    branch: branch,
    client: client
  } do
    source_id = active_source(branch, client)

    assert {:ok, notice} =
             Notifications.publish(client.id, %{title: "Offer", body: "Text"},
               idempotency_key: source_id,
               source_type: "marketing_reward",
               source_id: source_id,
               branch_id: branch.id,
               channels: [:in_app]
             )

    intent = Repo.get_by!(Intent, notification_id: notice.id, channel: "in_app")
    assert {:ok, generation} = Features.snapshot("notifications", {:branch, branch.id})

    args = %{
      intent_id: intent.id,
      optional_feature: "notifications",
      source_feature: "marketing_policies",
      scope_key: "branch:" <> branch.id,
      generation_franchise: generation.franchise,
      generation_branch: generation.branch
    }

    job = args |> DeliverWorker.new() |> Oban.insert!()
    job = %{job | args: job.args |> Jason.encode!() |> Jason.decode!()}
    Repo.update!(Ecto.Changeset.change(intent, status: "queued", job_id: job.id))

    assert :ok = DeliverWorker.perform(%{job | id: job.id + 1})
    assert Repo.get!(Intent, intent.id).status == "queued"

    assert {:ok, preview} = Features.disable_preview("notifications", {:branch, branch.id})

    assert {:ok, _} =
             Features.configure("notifications", {:branch, branch.id}, false,
               actor: "test",
               confirm_dependents: preview
             )

    assert {:ok, _} =
             Features.configure("notifications", {:branch, branch.id}, true, actor: "test")

    assert :ok = DeliverWorker.perform(job)
    assert Repo.get!(Intent, intent.id).status == "canceled"
  end

  test "source off and on cancels old queued delivery and cannot revive its send epoch", %{
    branch: branch,
    client: client
  } do
    source_id = active_source(branch, client)

    opts = [
      idempotency_key: source_id,
      source_type: "marketing_reward",
      source_id: source_id,
      branch_id: branch.id,
      channels: [:in_app]
    ]

    assert {:ok, notice} = Notifications.publish(client.id, %{title: "Offer", body: "Text"}, opts)
    intent = Repo.get_by!(Intent, notification_id: notice.id, channel: "in_app")

    job =
      %{
        intent_id: intent.id,
        optional_feature: "notifications",
        source_feature: "marketing_policies",
        scope_key: "branch:" <> branch.id,
        generation_franchise: notice.notification_generation_franchise,
        generation_branch: notice.notification_generation_branch
      }
      |> DeliverWorker.new()
      |> Oban.insert!()

    Repo.update!(Ecto.Changeset.change(intent, status: "queued", job_id: job.id))

    assert {:ok, _} =
             Features.configure("marketing_policies", {:branch, branch.id}, false, actor: "test")

    assert Repo.get!(Intent, intent.id).status == "canceled"
    assert Repo.get!(Oban.Job, job.id).state == "cancelled"

    assert {:ok, _} =
             Features.configure("marketing_policies", {:branch, branch.id}, true, actor: "test")

    assert {:error, :disabled} =
             Notifications.publish(client.id, %{title: "Offer", body: "Text"}, opts)

    assert :ok = DeliverWorker.perform(Repo.get!(Oban.Job, job.id))
    assert Repo.get!(Intent, intent.id).status == "canceled"
  end

  test "stale source epoch leaves no pending head that blocks a newer notice", %{
    branch: branch,
    client: client
  } do
    assert {:ok, _} = Notifications.update_consents(client.id, branch.id, %{push: true})
    old_source = active_source(branch, client)

    assert {:ok, old_notice} =
             Notifications.publish(client.id, %{title: "Old", body: "Text"},
               idempotency_key: old_source,
               source_type: "marketing_reward",
               source_id: old_source,
               branch_id: branch.id,
               channels: [:push]
             )

    sibling = insert(:branch)

    assert {:ok, _} =
             Features.configure("marketing_policies", {:branch, sibling.id}, true, actor: "test")

    new_source = active_source(branch, client)

    assert {:ok, new_notice} =
             Notifications.publish(client.id, %{title: "New", body: "Text"},
               idempotency_key: new_source,
               source_type: "marketing_reward",
               source_id: new_source,
               branch_id: branch.id,
               channels: [:push]
             )

    schedule = Repo.get_by!(Schedule, kind: "notifications.dispatch", scope_key: "franchise")
    Repo.update!(Ecto.Changeset.change(schedule, running: true, current_job_id: 123_987))
    assert {:ok, generation} = Features.snapshot("notifications", :franchise)

    context = %{
      feature: "notifications",
      scope: :franchise,
      generation: generation,
      schedule_id: schedule.id,
      job_id: 123_987
    }

    assert :ok = Dispatch.perform(:franchise, context)
    assert Repo.get_by!(Intent, notification_id: old_notice.id).status == "canceled"
    assert Repo.get_by!(Intent, notification_id: new_notice.id).status == "skipped"
  end

  test "push fanout progresses in bounded durable batches without sending during planning", %{
    branch: branch,
    client: client
  } do
    previous_limit = Application.get_env(:delivest, :background_pressure_limit)
    Application.put_env(:delivest, :background_pressure_limit, 1_000)

    on_exit(fn ->
      if previous_limit,
        do: Application.put_env(:delivest, :background_pressure_limit, previous_limit),
        else: Application.delete_env(:delivest, :background_pressure_limit)
    end)

    source_id = active_source(branch, client)
    assert {:ok, _} = Notifications.update_consents(client.id, branch.id, %{push: true})

    assert {:ok, notice} =
             Notifications.publish(client.id, %{title: "Offer", body: "Text"},
               idempotency_key: source_id,
               source_type: "marketing_reward",
               source_id: source_id,
               branch_id: branch.id,
               channels: [:push]
             )

    now = DateTime.utc_now(:second)

    for index <- 1..51 do
      Repo.insert_all("client_push_subscriptions", [
        %{
          id: Ecto.UUID.generate() |> Ecto.UUID.dump!(),
          client_id: Ecto.UUID.dump!(client.id),
          endpoint: "https://invalid.example/#{index}",
          p256dh: "key",
          auth: "key",
          locale: "ru",
          inserted_at: now,
          updated_at: now
        }
      ])
    end

    schedule = Repo.get_by!(Schedule, kind: "notifications.dispatch", scope_key: "franchise")
    Repo.update!(Ecto.Changeset.change(schedule, running: true, current_job_id: 123_456))
    assert {:ok, generation} = Features.snapshot("notifications", :franchise)

    context = %{
      feature: "notifications",
      scope: :franchise,
      generation: generation,
      schedule_id: schedule.id,
      job_id: 123_456
    }

    assert :ok = Dispatch.perform(:franchise, context)
    intent = Repo.get_by!(Intent, notification_id: notice.id, channel: "push")
    assert intent.status == "pending"
    assert Repo.aggregate(PushDelivery, :count) == 50
    assert :ok = Dispatch.perform(:franchise, context)
    assert Repo.get!(Intent, intent.id).status == "queued"
    assert Repo.aggregate(PushDelivery, :count) == 51

    delivery = Repo.one!(from d in PushDelivery, limit: 1)
    job = Repo.get!(Oban.Job, delivery.job_id)
    assert :ok = PushDeliveryWorker.perform(%{job | id: job.id + 1})
    assert Repo.get!(PushDelivery, delivery.id).status == "queued"
    other_client = insert(:client)

    Repo.update_all(
      from(s in Delivest.Push.ClientSubscription, where: s.id == ^delivery.subscription_id),
      set: [client_id: other_client.id]
    )

    assert :ok = PushDeliveryWorker.perform(job)
    assert Repo.get!(PushDelivery, delivery.id).last_error == "subscription_removed"
    assert :ok = PushDeliveryWorker.perform(job)

    second = Repo.one!(from d in PushDelivery, where: d.id != ^delivery.id, limit: 1)
    assert {:ok, _} = Notifications.update_consents(client.id, branch.id, %{push: false})
    assert :ok = PushDeliveryWorker.perform(Repo.get!(Oban.Job, second.job_id))
    assert Repo.get!(PushDelivery, second.id).last_error == "no_consent"
  end

  test "expired push endpoint is removed only while its account and keys still match", %{
    branch: branch,
    client: client
  } do
    source_id = active_source(branch, client)
    assert {:ok, _} = Notifications.update_consents(client.id, branch.id, %{push: true})

    assert {:ok, notice} =
             Notifications.publish(client.id, %{title: "Offer", body: "Text"},
               idempotency_key: source_id,
               source_type: "marketing_reward",
               source_id: source_id,
               branch_id: branch.id,
               channels: [:push]
             )

    first = Push.subscribe_client(client, PushClient.new() |> PushClient.subscription_attrs())
    second = Push.subscribe_client(client, PushClient.new() |> PushClient.subscription_attrs())
    assert {:ok, first} = first
    assert {:ok, second} = second

    schedule = Repo.get_by!(Schedule, kind: "notifications.dispatch", scope_key: "franchise")
    Repo.update!(Ecto.Changeset.change(schedule, running: true, current_job_id: 654_321))
    assert {:ok, generation} = Features.snapshot("notifications", :franchise)

    context = %{
      feature: "notifications",
      scope: :franchise,
      generation: generation,
      schedule_id: schedule.id,
      job_id: 654_321
    }

    assert :ok = Dispatch.perform(:franchise, context)
    intent = Repo.get_by!(Intent, notification_id: notice.id, channel: "push")
    deliveries = Repo.all(from d in PushDelivery, where: d.intent_id == ^intent.id)
    by_subscription = Map.new(deliveries, &{&1.subscription_id, &1})

    Req.Test.stub(Delivest.Push.Sender, &Plug.Conn.send_resp(&1, 410, ""))
    first_job = Repo.get!(Oban.Job, by_subscription[first.id].job_id)
    assert :ok = PushDeliveryWorker.perform(first_job)
    refute Repo.get(ClientSubscription, first.id)

    other_client = insert(:client)

    Req.Test.stub(Delivest.Push.Sender, fn conn ->
      Repo.update_all(from(s in ClientSubscription, where: s.id == ^second.id),
        set: [client_id: other_client.id]
      )

      Plug.Conn.send_resp(conn, 410, "")
    end)

    second_job = Repo.get!(Oban.Job, by_subscription[second.id].job_id)
    assert :ok = PushDeliveryWorker.perform(second_job)
    assert Repo.get!(ClientSubscription, second.id).client_id == other_client.id
  end

  defp active_source(branch, client) do
    assert {:ok, _} = Features.configure("marketing_policies", :franchise, true, actor: "test")

    assert {:ok, _} =
             Features.configure("marketing_policies", {:branch, branch.id}, true, actor: "test")

    segment = Repo.insert!(%Segment{name: "Audience", kind: :manual, scope: :branches})
    cart = Repo.insert!(%Cart{branch_id: branch.id, client_id: client.id})

    order =
      Repo.insert!(%Order{
        branch_id: branch.id,
        client_id: client.id,
        cart_id: cart.id,
        number: "N-#{Ecto.UUID.generate()}",
        daily_number: :erlang.unique_integer([:positive]),
        business_date: Date.utc_today(),
        status: :completed,
        total_amount: 100
      })

    Repo.insert!(%OrderTransition{
      order_id: order.id,
      from: :delivering,
      to: :completed,
      source: :system
    })

    policy =
      Repo.insert!(%Policy{
        name: "Offer",
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

    Repo.insert_all("marketing_policy_branches", [
      %{policy_id: Ecto.UUID.dump!(policy.id), branch_id: Ecto.UUID.dump!(branch.id)}
    ])

    now = DateTime.utc_now(:second)

    assert {:ok, source_generation} =
             Features.snapshot("marketing_policies", {:branch, branch.id})

    reward =
      Repo.insert!(%Entry{
        client_id: client.id,
        branch_id: branch.id,
        kind: :accrual,
        amount: 1,
        remaining: 1,
        expires_at: DateTime.add(now, 86_400, :second)
      })

    issue =
      Repo.insert!(%Issue{
        policy_id: policy.id,
        client_id: client.id,
        cycle_order_id: order.id,
        branch_id: branch.id,
        reward_type: "bonus",
        reward_id: reward.id,
        reward_amount: 1,
        issued_at: now,
        expires_at: DateTime.add(now, 86_400, :second),
        attribution_until: DateTime.add(now, 86_400, :second),
        policy_revision: 1,
        source_generation_franchise: source_generation.franchise,
        source_generation_branch: source_generation.branch
      })

    issue.id
  end
end
