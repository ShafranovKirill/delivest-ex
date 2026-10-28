defmodule Delivest.PushTest do
  use Delivest.DataCase, async: true
  use Oban.Testing, repo: Delivest.Repo

  import Delivest.Factory

  alias Delivest.{Oms, Push, PushClient}
  alias Delivest.Oms.Carts
  alias Delivest.Push.{Subscription, Vapid, Worker}

  setup do
    branch = insert(:branch, is_active: true)
    product = insert_branch_product(branch.id, price: 100)
    {:ok, cart} = Carts.create_cart(%{session_id: "push-#{branch.id}", branch_id: branch.id})
    {:ok, _, _} = Carts.add_item(cart.id, product.id, 1)

    {:ok, order} =
      Oms.create_order(%{
        "cart_id" => cart.id,
        "branch_id" => branch.id,
        "fulfillment_type" => "pickup",
        "payment_method" => "cash"
      })

    client = PushClient.new()
    {:ok, subscription} = Push.subscribe(order, PushClient.subscription_attrs(client))

    test_pid = self()

    Req.Test.stub(Delivest.Push.Sender, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:push, conn.req_headers, body})
      Plug.Conn.send_resp(conn, 201, "")
    end)

    %{order: order, client: client, subscription: subscription}
  end

  test "a status change sends an encrypted message once", %{order: order, client: client} do
    {:ok, order} = Oms.advance_order(order, :preparing, :system)
    assert_enqueued(worker: Worker, args: %{"order_id" => order.id})

    assert :ok = perform_job(Worker, %{"order_id" => order.id})
    assert_received {:push, headers, body}

    assert {"authorization", "vapid t=" <> _rest} = List.keyfind(headers, "authorization", 0)

    assert %{"body" => text, "tag" => tag, "icon" => nil, "url" => url} =
             PushClient.decrypt(client, body)

    assert url == "/" <> Repo.get!(Delivest.Identity.Branch, order.branch_id).slug
    assert text == "Order #{order.number} is being prepared"
    assert tag == "order-#{order.id}"

    assert :ok = perform_job(Worker, %{"order_id" => order.id})
    refute_received {:push, _headers, _body}
  end

  test "a gone subscription is dropped", %{order: order, subscription: subscription} do
    Req.Test.stub(Delivest.Push.Sender, &Plug.Conn.send_resp(&1, 410, ""))
    {:ok, order} = Oms.advance_order(order, :ready, :system)

    assert :ok = perform_job(Worker, %{"order_id" => order.id})
    refute Repo.get(Subscription, subscription.id)
  end

  test "a failed delivery is retried later", %{order: order, subscription: subscription} do
    Req.Test.stub(Delivest.Push.Sender, &Plug.Conn.send_resp(&1, 500, ""))
    {:ok, order} = Oms.advance_order(order, :ready, :system)

    assert {:error, :push_failed} = perform_job(Worker, %{"order_id" => order.id})
    assert %{notified_status: "created"} = Repo.get(Subscription, subscription.id)
  end

  test "a finished order forgets its subscriptions", %{order: order, subscription: subscription} do
    {:ok, order} =
      Oms.cancel_order(order, :system, %{"cancel_reason" => "other"})

    assert :ok = perform_job(Worker, %{"order_id" => order.id})
    assert_received {:push, _headers, _body}
    refute Repo.get(Subscription, subscription.id)
  end

  test "rejects malformed subscriptions", %{order: order} do
    assert {:error, changeset} =
             Push.subscribe(order, %{endpoint: "http://x", p256dh: "short", auth: "!"})

    assert %{endpoint: _, p256dh: _, auth: _} = errors_on(changeset)

    attrs =
      Map.put(PushClient.subscription_attrs(PushClient.new()), :endpoint, "https://10.0.0.1/x")

    assert {:error, changeset} = Push.subscribe(order, attrs)
    assert %{endpoint: ["is not a known push service"]} = errors_on(changeset)
  end

  test "the vapid token is signed for the push service origin" do
    "vapid t=" <> rest = Vapid.authorization("https://push.example.com/send/1")
    [token, "k=" <> public_key] = String.split(rest, ", ")
    [header, claims, signature] = String.split(token, ".")

    assert %{"aud" => "https://push.example.com"} =
             claims |> Base.url_decode64!(padding: false) |> Jason.decode!()

    <<r::unsigned-big-256, s::unsigned-big-256>> = Base.url_decode64!(signature, padding: false)
    der = :public_key.der_encode(:"ECDSA-Sig-Value", {:"ECDSA-Sig-Value", r, s})
    key = Base.url_decode64!(public_key, padding: false)

    assert :crypto.verify(:ecdsa, :sha256, header <> "." <> claims, der, [key, :prime256v1])
    assert public_key == Push.public_key()
  end
end
