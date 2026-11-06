defmodule DelivestWeb.Client.PushControllerTest do
  use DelivestWeb.ConnCase, async: true

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Oms.Order
  alias Delivest.Push
  alias Delivest.Push.Dispatch
  alias Delivest.Push.ClientSubscription
  alias Delivest.PushClient
  alias Delivest.Push.Subscription
  alias Delivest.Repo
  alias DelivestWeb.ClientToken

  setup %{conn: conn} do
    branch = insert(:branch, is_active: true)
    product = insert_branch_product(branch.id, price: 300)
    conn = put_req_header(conn, "x-forwarded-for", "push-#{System.unique_integer([:positive])}")

    conn = conn |> post(~p"/client/branches/#{branch.id}/select") |> recycle_forwarded()
    conn = conn |> get(~p"/client/cart?branch_id=#{branch.id}")
    cart_id = json_response(conn, 200)["data"]["id"]
    conn = conn |> recycle_forwarded() |> post(~p"/client/cart/#{cart_id}/items/#{product.id}")

    conn =
      conn
      |> recycle_forwarded()
      |> post(~p"/client/orders", %{
        "cart_id" => cart_id,
        "branch_id" => branch.id,
        "fulfillment_type" => "pickup",
        "payment_method" => "cash",
        "customer_phone" => "+79990001122"
      })

    order_id = json_response(conn, 200)["data"]["id"]
    %{conn: recycle_forwarded(conn), order_id: order_id, branch: branch}
  end

  defp recycle_forwarded(conn) do
    forwarded = get_req_header(conn, "x-forwarded-for")
    conn |> recycle() |> put_req_header("x-forwarded-for", Enum.join(forwarded, ","))
  end

  test "gives the public key", %{conn: conn} do
    assert %{"data" => %{"public_key" => key}} =
             conn |> get(~p"/client/push/key") |> json_response(200)

    assert byte_size(Base.url_decode64!(key, padding: false)) == 65
  end

  test "subscribes the browser to an order of the session", %{conn: conn, order_id: order_id} do
    client = PushClient.new()

    assert conn
           |> post(~p"/client/orders/#{order_id}/push", client.attrs)
           |> response(204)

    assert [%{order_id: ^order_id, locale: "en", notified_status: "created"}] =
             Repo.all(Subscription)
  end

  test "another session cannot subscribe", %{order_id: order_id} do
    assert %{"error" => "order_not_found"} =
             build_conn()
             |> post(~p"/client/orders/#{order_id}/push", PushClient.new().attrs)
             |> json_response(404)
  end

  test "rejects a broken subscription", %{conn: conn, order_id: order_id} do
    assert %{"error" => "invalid_subscription"} =
             conn
             |> post(~p"/client/orders/#{order_id}/push", %{"endpoint" => "https://x"})
             |> json_response(422)
  end

  test "subscribes a signed-in client to loyalty reminders once" do
    client = insert(:client)
    device = PushClient.new()

    assert authed(client) |> post(~p"/client/push", device.attrs) |> response(204)
    assert authed(client) |> post(~p"/client/push", device.attrs) |> response(204)

    assert [%ClientSubscription{client_id: client_id, locale: "en"}] =
             Repo.all(ClientSubscription)

    assert client_id == client.id
  end

  test "unsubscribes a signed-in client by endpoint" do
    client = insert(:client)
    device = PushClient.new()

    assert authed(client) |> post(~p"/client/push", device.attrs) |> response(204)

    endpoint = URI.encode_query(%{endpoint: device.attrs["endpoint"]})
    assert authed(client) |> delete("/client/push?" <> endpoint) |> response(204)

    assert Repo.all(ClientSubscription) == []
  end

  test "logout cleanup removes only the previous client's device subscriptions", %{
    conn: conn,
    order_id: guest_order_id,
    branch: branch
  } do
    client_a = insert(:client)
    client_b = insert(:client)
    device = PushClient.new()
    endpoint = URI.encode_query(%{endpoint: device.attrs["endpoint"]})
    guest_order = Repo.get!(Order, guest_order_id)
    assert guest_order.guest_session_access

    order_a =
      branch.id
      |> order_fixture(attrs: %{"session_id" => guest_order.session_id})
      |> Ecto.Changeset.change(client_id: client_a.id)
      |> Repo.update!()

    order_b =
      branch.id
      |> order_fixture(attrs: %{"session_id" => guest_order.session_id})
      |> Ecto.Changeset.change(client_id: client_b.id)
      |> Repo.update!()

    for order <- [guest_order, order_a, order_b] do
      assert {:ok, _} = Push.subscribe(order, PushClient.subscription_attrs(device))
    end

    for client <- [client_a, client_b] do
      assert {:ok, _} = Push.subscribe_client(client, PushClient.subscription_attrs(device))
    end

    old_conn =
      put_req_header(
        conn,
        "authorization",
        "Bearer " <> ClientToken.issue(client_a.id).access_token
      )

    assert old_conn |> delete("/client/push?" <> endpoint) |> response(204)
    assert old_conn |> delete("/client/push?" <> endpoint) |> response(204)

    assert Repo.all(ClientSubscription) |> Enum.map(& &1.client_id) == [client_b.id]
    assert Repo.all(Subscription) |> Enum.map(& &1.order_id) == [order_b.id]

    Req.Test.stub(Delivest.Push.Sender, fn _conn -> flunk("old device must not be notified") end)
    assert :ok = Dispatch.run(order_a.id)
  end

  test "rejects a broken client subscription" do
    client = insert(:client)

    assert %{"error" => "invalid_subscription"} =
             authed(client)
             |> post(~p"/client/push", %{"endpoint" => "https://x"})
             |> json_response(422)
  end

  defp authed(client) do
    put_req_header(
      build_conn(),
      "authorization",
      "Bearer " <> ClientToken.issue(client.id).access_token
    )
  end
end
