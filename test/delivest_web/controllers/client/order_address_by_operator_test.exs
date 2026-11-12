defmodule DelivestWeb.Client.OrderAddressByOperatorTest do
  use DelivestWeb.ConnCase, async: true

  import Delivest.Factory

  alias Delivest.Delivery
  alias Delivest.Oms.Order
  alias Delivest.Repo

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

    {:ok, _} = Delivery.update_settings(admin, branch.id, %{"mode" => "flat"})

    conn =
      put_req_header(conn, "x-forwarded-for", "operator-#{System.unique_integer([:positive])}")

    {conn, cart_id} = cart(conn, branch, product)

    payload = %{
      "cart_id" => cart_id,
      "branch_id" => branch.id,
      "fulfillment_type" => "delivery",
      "payment_method" => "cash",
      "customer_phone" => "+79990001122",
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
             "operator_address" => true
           }
  end
end
