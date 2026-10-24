defmodule DelivestWeb.Client.PushControllerTest do
  use DelivestWeb.ConnCase, async: true

  import Delivest.Factory

  alias Delivest.PushClient
  alias Delivest.Push.Subscription
  alias Delivest.Repo

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
    %{conn: recycle_forwarded(conn), order_id: order_id}
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
end
