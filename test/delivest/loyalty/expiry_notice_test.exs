defmodule Delivest.Loyalty.ExpiryNoticeTest do
  use Delivest.DataCase, async: false
  use Oban.Testing, repo: Delivest.Repo

  import Delivest.Factory

  alias Delivest.{Push, PushClient, Repo}

  alias Delivest.Loyalty.{
    Entry,
    ExpiryDelivery,
    ExpiryDeliveryWorker,
    ExpiryNoticeWorker,
    ExpiryNotification
  }

  alias Delivest.Push.ClientSubscription

  setup do
    Cachex.clear(:franchise_cache)
    on_exit(fn -> Cachex.clear(:franchise_cache) end)

    branch = insert(:branch, is_active: true)
    client = insert(:client)
    device = PushClient.new()
    {:ok, _subscription} = Push.subscribe_client(client, PushClient.subscription_attrs(device))

    test_pid = self()

    Req.Test.stub(Delivest.Push.Sender, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:push, conn.request_path, body})
      Plug.Conn.send_resp(conn, 201, "")
    end)

    %{branch: branch, client: client, device: device}
  end

  test "reminds the client a week before the stars expire", ctx do
    entry = entry(ctx, 6)
    expires_on = date(entry)

    assert :ok = run_notice()

    assert_received {:push, path, body}
    assert path == URI.parse(ctx.device.attrs["endpoint"]).path

    assert %{"body" => text, "tag" => tag, "url" => url} = PushClient.decrypt(ctx.device, body)
    assert text == "Stars expiring soon: 10. Use them before #{expires_on}."
    assert tag == "loyalty-expiry-#{expires_on}"
    assert url == "/#{ctx.branch.slug}/stars"

    assert [%ExpiryNotification{expires_on: notified_on}] = Repo.all(ExpiryNotification)
    assert Date.to_string(notified_on) == expires_on
  end

  test "does not repeat the same reminder", ctx do
    entry(ctx, 6)

    assert :ok = run_notice()
    assert_received {:push, _path, _body}

    assert :ok = run_notice()
    refute_received {:push, _path, _body}
    assert length(Repo.all(ExpiryNotification)) == 1
  end

  test "ignores stars that expire later than a week", ctx do
    entry(ctx, 8)

    assert :ok = run_notice()

    refute_received {:push, _path, _body}
    assert Repo.all(ExpiryNotification) == []
  end

  test "drops a subscription the push service no longer knows", ctx do
    entry(ctx, 6)
    Req.Test.stub(Delivest.Push.Sender, &Plug.Conn.send_resp(&1, 410, ""))

    assert :ok = run_notice()

    assert Repo.all(ClientSubscription) == []
    assert length(Repo.all(ExpiryNotification)) == 1
    assert [%ExpiryDelivery{status: :expired}] = Repo.all(ExpiryDelivery)
  end

  test "a legacy marker does not enqueue new deliveries", ctx do
    expiry = entry(ctx, 6) |> Map.get(:expires_at) |> DateTime.to_date()
    Repo.insert!(%ExpiryNotification{client_id: ctx.client.id, expires_on: expiry})

    assert :ok = perform_job(ExpiryNoticeWorker, %{})
    assert Repo.all(ExpiryDelivery) == []
    refute_enqueued worker: ExpiryDeliveryWorker
  end

  test "uses the subscription locale", ctx do
    entry(ctx, 6)

    locale = Map.put(PushClient.subscription_attrs(ctx.device), :locale, "ru")
    {:ok, _subscription} = Push.subscribe_client(ctx.client, locale)

    assert :ok = run_notice()

    assert_received {:push, _path, body}

    assert %{"body" => "Сгорят звёзды: 10. Успейте обменять до " <> _rest} =
             PushClient.decrypt(ctx.device, body)
  end

  test "marker, device delivery and job roll back together", ctx do
    entry(ctx, 6)

    assert {:error, :undo} =
             Repo.transaction(fn ->
               assert :ok = perform_job(ExpiryNoticeWorker, %{})
               assert Repo.aggregate(ExpiryNotification, :count, :id) == 1
               assert Repo.aggregate(ExpiryDelivery, :count, :id) == 1
               assert_enqueued worker: ExpiryDeliveryWorker
               Repo.rollback(:undo)
             end)

    assert Repo.all(ExpiryNotification) == []
    assert Repo.all(ExpiryDelivery) == []
    refute_enqueued worker: ExpiryDeliveryWorker
  end

  test "a retryable response on one device preserves the other delivery", ctx do
    entry(ctx, 6)
    second = PushClient.new()

    {:ok, second_subscription} =
      Push.subscribe_client(ctx.client, PushClient.subscription_attrs(second))

    first_path = URI.parse(ctx.device.attrs["endpoint"]).path
    second_path = URI.parse(second.attrs["endpoint"]).path
    counter = start_supervised!({Agent, fn -> %{} end})

    Req.Test.stub(Delivest.Push.Sender, fn conn ->
      attempt =
        Agent.get_and_update(counter, fn counts ->
          count = Map.get(counts, conn.request_path, 0) + 1
          {count, Map.put(counts, conn.request_path, count)}
        end)

      if conn.request_path == second_path and attempt == 1,
        do: Plug.Conn.send_resp(conn, 503, ""),
        else: Plug.Conn.send_resp(conn, 201, "")
    end)

    assert :ok = perform_job(ExpiryNoticeWorker, %{})
    assert %{failure: 1, success: 1} = Oban.drain_queue(queue: :notifications)

    second_delivery = Repo.get_by!(ExpiryDelivery, subscription_id: second_subscription.id)
    assert second_delivery.status == :pending
    assert :ok = perform_job(ExpiryDeliveryWorker, %{delivery_id: second_delivery.id}, attempt: 2)
    assert Repo.reload!(second_delivery).status == :delivered
    assert %{^first_path => 1, ^second_path => 2} = Agent.get(counter, & &1)
    assert Repo.aggregate(ExpiryDelivery, :count, :id) == 2
  end

  test "the last retryable response records a terminal failure", ctx do
    entry(ctx, 6)
    Req.Test.stub(Delivest.Push.Sender, &Plug.Conn.send_resp(&1, 503, ""))
    assert :ok = perform_job(ExpiryNoticeWorker, %{})
    [delivery] = Repo.all(ExpiryDelivery)

    assert {:error, {:http_error, 503}} =
             perform_job(ExpiryDeliveryWorker, %{delivery_id: delivery.id}, attempt: 3)

    assert Repo.reload!(delivery).status == :failed
    assert Repo.reload!(delivery).attempts == 1
  end

  test "a timeout is unknown and duplicate execution cannot resend", ctx do
    entry(ctx, 6)
    counter = start_supervised!({Agent, fn -> 0 end})

    Req.Test.stub(Delivest.Push.Sender, fn conn ->
      Agent.update(counter, &(&1 + 1))
      Req.Test.transport_error(conn, :timeout)
    end)

    assert :ok = run_notice()
    [delivery] = Repo.all(ExpiryDelivery)
    assert delivery.status == :unknown
    assert delivery.last_error == "unconfirmed:#{delivery.id}"
    assert :ok = perform_job(ExpiryDeliveryWorker, %{delivery_id: delivery.id})
    assert Agent.get(counter, & &1) == 1
  end

  test "stale sending is unknown without another request", ctx do
    entry(ctx, 6)
    assert :ok = perform_job(ExpiryNoticeWorker, %{})
    [delivery] = Repo.all(ExpiryDelivery)

    Repo.update_all(from(d in ExpiryDelivery, where: d.id == ^delivery.id),
      set: [status: :sending, updated_at: DateTime.add(DateTime.utc_now(:second), -121, :second)]
    )

    expected = "expiry delivery unconfirmed: #{delivery.id}"

    assert {:cancel, ^expected} =
             perform_job(ExpiryDeliveryWorker, %{delivery_id: delivery.id}, attempt: 2)

    assert Repo.reload!(delivery).status == :unknown
    refute_received {:push, _path, _body}
  end

  test "recent sending snoozes until it can be marked unknown", ctx do
    entry(ctx, 6)
    assert :ok = perform_job(ExpiryNoticeWorker, %{})
    [delivery] = Repo.all(ExpiryDelivery)

    Repo.update_all(from(d in ExpiryDelivery, where: d.id == ^delivery.id),
      set: [status: :sending, updated_at: DateTime.utc_now(:second)]
    )

    assert {:snooze, seconds} =
             perform_job(ExpiryDeliveryWorker, %{delivery_id: delivery.id}, attempt: 2)

    assert seconds in 1..120
    assert Repo.reload!(delivery).status == :sending
    refute_received {:push, _path, _body}
  end

  test "the next cron run marks a terminally crashed sending job unknown", ctx do
    entry(ctx, 6)
    assert :ok = perform_job(ExpiryNoticeWorker, %{})
    [delivery] = Repo.all(ExpiryDelivery)

    Repo.update_all(from(d in ExpiryDelivery, where: d.id == ^delivery.id),
      set: [status: :sending, updated_at: DateTime.add(DateTime.utc_now(:second), -121, :second)]
    )

    assert :ok = perform_job(ExpiryNoticeWorker, %{})
    assert %ExpiryDelivery{status: :unknown, last_error: error} = Repo.reload!(delivery)
    assert error == "stale:#{delivery.id}"
    refute_received {:push, _path, _body}
  end

  test "a late queued delivery is not sent after the stars expire", ctx do
    entry(ctx, 6)
    assert :ok = perform_job(ExpiryNoticeWorker, %{})
    [notification] = Repo.all(ExpiryNotification)

    Repo.update_all(from(n in ExpiryNotification, where: n.id == ^notification.id),
      set: [expires_at: DateTime.add(DateTime.utc_now(:second), -1, :second)]
    )

    [delivery] = Repo.all(ExpiryDelivery)
    assert :ok = perform_job(ExpiryDeliveryWorker, %{delivery_id: delivery.id})
    assert Repo.reload!(delivery).status == :expired
    refute_received {:push, _path, _body}
  end

  defp entry(ctx, days) do
    Repo.insert!(%Entry{
      client_id: ctx.client.id,
      branch_id: ctx.branch.id,
      kind: :accrual,
      amount: 10,
      remaining: 10,
      expires_at: DateTime.add(DateTime.utc_now(:second), days, :day)
    })
  end

  defp date(entry), do: entry.expires_at |> DateTime.to_date() |> Date.to_string()

  defp run_notice do
    with :ok <- perform_job(ExpiryNoticeWorker, %{}) do
      Oban.drain_queue(queue: :notifications)
      :ok
    end
  end
end
