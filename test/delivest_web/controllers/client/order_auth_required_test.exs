defmodule DelivestWeb.Client.OrderAuthRequiredTest do
  use DelivestWeb.ConnCase, async: false

  import Delivest.Factory

  alias Delivest.Franchise
  alias Delivest.Oms.Order
  alias Delivest.Repo
  alias DelivestWeb.ClientToken

  setup %{conn: conn} do
    Cachex.clear(:franchise_cache)
    branch = insert(:branch, is_active: true)
    product = insert_branch_product(branch.id, price: 300)
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))
    %{conn: conn, branch: branch, product: product, admin: admin}
  end

  test "the setting requires a configured sign-in method", %{admin: admin} do
    assert {:error, changeset} =
             Franchise.update_settings(admin, %{"client_auth_required" => true})

    assert Keyword.has_key?(changeset.errors, :client_auth_required)
    refute Franchise.get_settings().client_auth_required

    insert(:zvonok_settings)

    assert {:ok, %{client_auth_required: true}} =
             Franchise.update_settings(admin, %{"client_auth_required" => true})
  end

  test "guest order is refused before side effects, signed-in client succeeds", context do
    %{conn: conn, branch: branch, product: product, admin: admin} = context
    insert(:zvonok_settings)
    {:ok, _} = Franchise.update_settings(admin, %{"client_auth_required" => true})

    assert %{"data" => %{"client_auth_required" => true}} =
             conn |> get(~p"/client/franchise") |> json_response(200)

    conn = conn |> recycle() |> post(~p"/client/branches/#{branch.id}/select")
    conn = conn |> recycle() |> get(~p"/client/cart?branch_id=#{branch.id}")
    cart_id = json_response(conn, 200)["data"]["id"]
    conn = conn |> recycle() |> post(~p"/client/cart/#{cart_id}/items/#{product.id}")
    assert json_response(conn, 200)

    attrs = %{
      cart_id: cart_id,
      branch_id: branch.id,
      fulfillment_type: "pickup",
      payment_method: "cash",
      customer_phone: "+79990001122"
    }

    assert %{"error" => "client_auth_required"} =
             conn |> recycle() |> post(~p"/client/orders", attrs) |> json_response(401)

    assert Repo.aggregate(Order, :count) == 0

    client = insert(:client, phone: "+79990001122")
    access = ClientToken.issue(client.id).access_token

    assert %{"data" => %{"id" => id}} =
             conn
             |> recycle()
             |> put_req_header("authorization", "Bearer " <> access)
             |> post(~p"/client/orders", attrs)
             |> json_response(200)

    assert Repo.get!(Order, id).client_id == client.id
  end
end
