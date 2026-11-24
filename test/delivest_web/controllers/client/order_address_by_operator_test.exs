defmodule DelivestWeb.Client.OrderAddressByOperatorTest do
  use DelivestWeb.ConnCase, async: true

  import Delivest.Factory

  alias Delivest.Delivery
  alias Delivest.Identity
  alias Delivest.Oms.Order
  alias Delivest.Repo
  alias DelivestWeb.ClientToken

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

  test "a delivery order without address is accepted when the customer calls the operator", %{
    conn: conn
  } do
    branch = insert(:branch, is_active: true)
    product = insert_branch_product(branch.id, price: 300)
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))

    {:ok, _} =
      Delivery.update_settings(admin, branch.id, %{
        "mode" => "flat",
        "map_address" => false,
        "operator_address" => true
      })

    conn =
      put_req_header(conn, "x-forwarded-for", "operator-#{System.unique_integer([:positive])}")

    {conn, cart_id} = cart(conn, branch, product)

    payload = %{
      "cart_id" => cart_id,
      "branch_id" => branch.id,
      "fulfillment_type" => "delivery",
      "payment_method" => "cash",
      "customer_phone" => build(:client).phone,
      "address_by_operator" => true
    }

    data =
      conn
      |> post(~p"/client/orders", payload)
      |> json_response(200)
      |> Map.fetch!("data")

    assert %Order{address_by_operator: true, address: address} = Repo.get!(Order, data["id"])
    refute address && address.street
  end

  test "the branch reports the address settings to the client", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    insert_branch_product(branch.id, price: 300)

    Delivest.Repo.insert!(%Delivest.Identity.Branch.BranchInfo{
      branch_id: branch.id,
      address: "Ленина, 1"
    })

    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))

    {:ok, _} =
      Delivery.update_settings(admin, branch.id, %{
        "mode" => "flat",
        "map_address" => "false",
        "operator_address" => "true"
      })

    data =
      conn |> get(~p"/client/branches") |> json_response(200) |> Map.fetch!("data")

    branch_payload = Enum.find(data, &(&1["id"] == branch.id))

    assert branch_payload["branch_info"]["delivery"] == %{
             "map_address" => false,
             "address_mode_set" => false,
             "show_city" => false,
             "operator_address" => true
           }
  end

  test "public checkout rejects operator address when the branch has not enabled it", %{
    conn: conn
  } do
    branch = insert(:branch, is_active: true)
    product = insert_branch_product(branch.id, price: 300)

    conn =
      put_req_header(
        conn,
        "x-forwarded-for",
        "operator-disabled-#{System.unique_integer([:positive])}"
      )

    {conn, cart_id} = cart(conn, branch, product)

    payload = %{
      "cart_id" => cart_id,
      "branch_id" => branch.id,
      "fulfillment_type" => "delivery",
      "payment_method" => "cash",
      "customer_phone" => build(:client).phone,
      "address_by_operator" => true
    }

    assert %{"error" => "address_by_operator_unavailable"} =
             conn |> post(~p"/client/orders", payload) |> json_response(422)
  end

  test "explicit map mode requires coordinates", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    product = insert_branch_product(branch.id, price: 300)
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))

    {:ok, _} =
      Delivery.update_settings(admin, branch.id, %{
        "map_address" => true,
        "address_mode_set" => true
      })

    conn =
      put_req_header(
        conn,
        "x-forwarded-for",
        "map-required-#{System.unique_integer([:positive])}"
      )

    {conn, cart_id} = cart(conn, branch, product)

    payload = %{
      "cart_id" => cart_id,
      "branch_id" => branch.id,
      "fulfillment_type" => "delivery",
      "payment_method" => "cash",
      "customer_phone" => build(:client).phone,
      "address" => %{"street" => "Ленина", "house" => "1"}
    }

    assert %{"error" => "delivery_no_coordinates"} =
             conn |> post(~p"/client/orders", payload) |> json_response(422)
  end

  test "explicit manual mode accepts a freeform street without a separate house", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    product = insert_branch_product(branch.id, price: 300)
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))

    {:ok, _} =
      Delivery.update_settings(admin, branch.id, %{
        "mode" => "flat",
        "map_address" => false,
        "address_mode_set" => true
      })

    conn = put_req_header(conn, "x-forwarded-for", "manual-#{System.unique_integer([:positive])}")
    {conn, cart_id} = cart(conn, branch, product)

    payload = %{
      "cart_id" => cart_id,
      "branch_id" => branch.id,
      "fulfillment_type" => "delivery",
      "payment_method" => "cash",
      "customer_phone" => build(:client).phone,
      "address" => %{"street" => "Ленина, 1", "house" => ""}
    }

    data = conn |> post(~p"/client/orders", payload) |> json_response(200) |> Map.fetch!("data")
    assert %Order{address: %{street: "Ленина, 1", house: nil}} = Repo.get!(Order, data["id"])

    assert %{"error" => "incomplete_delivery_address"} =
             conn
             |> recycle_with_ip()
             |> post(~p"/client/orders", put_in(payload, ["address", "street"], "  "))
             |> json_response(422)
  end

  test "explicit map mode accepts a saved coordinate and requires the house", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    product = insert_branch_product(branch.id, price: 300)
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))

    {:ok, _} =
      Delivery.update_settings(admin, branch.id, %{
        "mode" => "flat",
        "map_address" => true,
        "address_mode_set" => true
      })

    conn = put_req_header(conn, "x-forwarded-for", "saved-#{System.unique_integer([:positive])}")
    {conn, cart_id} = cart(conn, branch, product)

    payload = %{
      "cart_id" => cart_id,
      "branch_id" => branch.id,
      "fulfillment_type" => "delivery",
      "payment_method" => "cash",
      "customer_phone" => build(:client).phone,
      "address" => %{"street" => "Ленина", "latitude" => 55.75, "longitude" => 37.61}
    }

    assert %{"error" => "incomplete_delivery_address"} =
             conn |> post(~p"/client/orders", payload) |> json_response(422)

    assert %{"data" => %{"id" => _}} =
             conn
             |> recycle_with_ip()
             |> post(~p"/client/orders", put_in(payload, ["address", "house"], "1"))
             |> json_response(200)
  end

  test "authenticated checkout remembers the full house line for the next order", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    product = insert_branch_product(branch.id, price: 300)
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))
    client = insert(:client)
    access = ClientToken.issue(client.id).access_token

    {:ok, _} =
      Delivery.update_settings(admin, branch.id, %{"mode" => "flat", "map_address" => false})

    conn = conn |> put_req_header("authorization", "Bearer " <> access)
    {conn, cart_id} = cart(conn, branch, product)

    payload = %{
      "cart_id" => cart_id,
      "branch_id" => branch.id,
      "fulfillment_type" => "delivery",
      "payment_method" => "cash",
      "address" => %{"street" => "Ленина", "house" => "7", "block" => "1", "building" => "2"}
    }

    assert %{"data" => %{"id" => _}} =
             conn |> post(~p"/client/orders", payload) |> json_response(200)

    assert [%{house: "7 к 1 стр 2"}] = Identity.list_client_addresses(client.id)
  end
end
