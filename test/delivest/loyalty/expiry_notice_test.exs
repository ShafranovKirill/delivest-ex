defmodule Delivest.Loyalty.ExpiryNoticeTest do
  use Delivest.DataCase, async: false
  use Oban.Testing, repo: Delivest.Repo

  import Delivest.Factory

  alias Delivest.{Push, PushClient, Repo}
  alias Delivest.Loyalty.{Entry, ExpiryNoticeWorker, ExpiryNotification}
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

    assert :ok = perform_job(ExpiryNoticeWorker, %{})

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

    assert :ok = perform_job(ExpiryNoticeWorker, %{})
    assert_received {:push, _path, _body}

    assert :ok = perform_job(ExpiryNoticeWorker, %{})
    refute_received {:push, _path, _body}
    assert length(Repo.all(ExpiryNotification)) == 1
  end

  test "ignores stars that expire later than a week", ctx do
    entry(ctx, 8)

    assert :ok = perform_job(ExpiryNoticeWorker, %{})

    refute_received {:push, _path, _body}
    assert Repo.all(ExpiryNotification) == []
  end

  test "drops a subscription the push service no longer knows", ctx do
    entry(ctx, 6)
    Req.Test.stub(Delivest.Push.Sender, &Plug.Conn.send_resp(&1, 410, ""))

    assert :ok = perform_job(ExpiryNoticeWorker, %{})

    assert Repo.all(ClientSubscription) == []
    assert length(Repo.all(ExpiryNotification)) == 1
  end

  test "uses the subscription locale", ctx do
    entry(ctx, 6)

    locale = Map.put(PushClient.subscription_attrs(ctx.device), :locale, "ru")
    {:ok, _subscription} = Push.subscribe_client(ctx.client, locale)

    assert :ok = perform_job(ExpiryNoticeWorker, %{})

    assert_received {:push, _path, body}

    assert %{"body" => "Сгорят звёзды: 10. Успейте обменять до " <> _rest} =
             PushClient.decrypt(ctx.device, body)
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
end
