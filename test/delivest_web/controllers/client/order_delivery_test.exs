defmodule DelivestWeb.Client.OrderDeliveryTest do
  use DelivestWeb.ConnCase, async: true

  import Delivest.Factory

  alias Delivest.Delivery
  alias Delivest.Oms.Order
  alias Delivest.Repo

  @square %{
    "type" => "Polygon",
    "coordinates" => [[[37.0, 55.0], [38.0, 55.0], [38.0, 56.0], [37.0, 56.0], [37.0, 55.0]]]
  }

  setup %{conn: conn} do
    branch = insert(:branch, is_active: true)
    product = insert_branch_product(branch.id, price: 300)
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))

    {:ok, _} = Delivery.update_settings(admin, branch.id, %{"mode" => "zones"})
    {:ok, zone} = Delivery.create_zone(admin, branch.id, @square)

    {:ok, _} =
      Delivery.update_zone(admin, branch.id, zone.id, %{
        "thresholds" => [
          %{"order_from" => 250, "price" => 150},
          %{"order_from" => 1000, "price" => 0}
        ]
      })

    conn =
      put_req_header(conn, "x-forwarded-for", "delivery-#{System.unique_integer([:positive])}")

    %{conn: conn, branch: branch, product: product, admin: admin}
  end

  defp cart(conn, branch, product) do
    conn = post(conn, ~p"/client/branches/#{branch.id}/select")
    conn = conn |> recycle_with_ip() |> get(~p"/client/cart?branch_id=#{branch.id}")
    cart_id = json_response(conn, 200)["data"]["id"]
    conn = conn |> recycle_with_ip() |> post(~p"/client/cart/#{cart_id}/items/#{product.id}")
    assert json_response(conn, 200)
    {recycle_with_ip(conn), cart_id}
  end

  defp recycle_with_ip(conn) do
    forwarded = get_req_header(conn, "x-forwarded-for")
    conn |> recycle() |> put_req_header("x-forwarded-for", Enum.join(forwarded, ","))
  end

  defp params(branch, cart_id, address) do
    %{
      "cart_id" => cart_id,
      "branch_id" => branch.id,
      "fulfillment_type" => "delivery",
      "payment_method" => "cash",
      "customer_phone" => "+79990001122",
      "address" => address
    }
  end

  test "the zone price is added to the order", %{conn: conn, branch: branch, product: product} do
    {conn, cart_id} = cart(conn, branch, product)
    address = %{"street" => "Ленина", "house" => "1", "latitude" => 55.5, "longitude" => 37.5}

    data =
      conn
      |> post(~p"/client/orders", params(branch, cart_id, address))
      |> json_response(200)
      |> Map.fetch!("data")

    assert %{"delivery_amount" => 150, "total_amount" => 450} = data
    assert %Order{delivery_amount: 150, total_amount: 450} = Repo.get!(Order, data["id"])
  end

  test "addresses outside the zones are refused", %{conn: conn, branch: branch, product: product} do
    {conn, cart_id} = cart(conn, branch, product)
    address = %{"street" => "Ленина", "house" => "1", "latitude" => 54.0, "longitude" => 37.5}

    assert %{"error" => "delivery_outside_zones"} =
             conn
             |> post(~p"/client/orders", params(branch, cart_id, address))
             |> json_response(422)
  end

  test "an address without a point is refused, no address at all is for the operator", %{
    conn: conn,
    branch: branch,
    product: product
  } do
    {conn, cart_id} = cart(conn, branch, product)

    assert %{"error" => "delivery_no_coordinates"} =
             conn
             |> post(
               ~p"/client/orders",
               params(branch, cart_id, %{"street" => "Ленина", "house" => "1"})
             )
             |> json_response(422)

    assert %{"data" => %{"delivery_amount" => 0}} =
             conn
             |> recycle_with_ip()
             |> post(~p"/client/orders", params(branch, cart_id, %{}))
             |> json_response(200)
  end

  test "a small order is refused with the minimum", %{
    conn: conn,
    branch: branch,
    product: product,
    admin: admin
  } do
    [zone] = Delivery.list_zones(branch.id)

    {:ok, _} =
      Delivery.update_zone(admin, branch.id, zone.id, %{
        "thresholds" => [%{"order_from" => 500, "price" => 150}]
      })

    {conn, cart_id} = cart(conn, branch, product)
    address = %{"street" => "Ленина", "house" => "1", "latitude" => 55.5, "longitude" => 37.5}

    assert %{"error" => "delivery_below_minimum", "details" => %{"min_order" => 500}} =
             conn
             |> post(~p"/client/orders", params(branch, cart_id, address))
             |> json_response(422)
  end

  test "pickup has no delivery price", %{conn: conn, branch: branch, product: product} do
    {conn, cart_id} = cart(conn, branch, product)

    assert %{"data" => %{"delivery_amount" => 0, "total_amount" => 300}} =
             conn
             |> post(
               ~p"/client/orders",
               Map.put(params(branch, cart_id, %{}), "fulfillment_type", "pickup")
             )
             |> json_response(200)
  end
end
