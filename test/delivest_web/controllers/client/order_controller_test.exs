defmodule DelivestWeb.Client.OrderControllerTest do
  use DelivestWeb.ConnCase, async: true

  import Delivest.Factory

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Crm.BranchSettings
  alias Delivest.Integrations.Frontpad
  alias Delivest.Oms.Order
  alias Delivest.Repo
  alias DelivestWeb.ClientToken

  setup %{conn: conn} do
    branch = insert(:branch, is_active: true)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{frontpad: %Frontpad.Settings{api_key: "super-secret-key"}}
    })

    product = insert_branch_product(branch.id, price: 300)

    client_ip = "client-#{System.unique_integer([:positive])}"
    conn = put_req_header(conn, "x-forwarded-for", "spoofed, #{client_ip}")

    %{conn: conn, branch: branch, product: product}
  end

  defp start_session(conn, branch) do
    conn = post(conn, ~p"/client/branches/#{branch.id}/select")
    assert json_response(conn, 200)
    recycle_with_headers(conn)
  end

  defp cart_with_product(conn, branch, product) do
    conn = get(conn, ~p"/client/cart?branch_id=#{branch.id}")
    cart_id = json_response(conn, 200)["data"]["id"]

    conn = post(recycle_with_headers(conn), ~p"/client/cart/#{cart_id}/items/#{product.id}")
    assert json_response(conn, 200)["data"]["total_amount"] == 300

    {recycle_with_headers(conn), cart_id}
  end

  defp recycle_with_headers(conn) do
    forwarded = get_req_header(conn, "x-forwarded-for")

    conn
    |> recycle()
    |> put_req_header("x-forwarded-for", Enum.join(forwarded, ","))
  end

  defp order_params(branch, cart_id, extra \\ %{}) do
    Map.merge(
      %{
        "cart_id" => cart_id,
        "branch_id" => branch.id,
        "fulfillment_type" => "pickup",
        "payment_method" => "cash",
        "customer_phone" => "+79990001122",
        "customer_name" => "Иван"
      },
      extra
    )
  end

  test "branch payload does not expose CRM credentials", %{conn: conn, branch: branch} do
    body = conn |> post(~p"/client/branches/#{branch.id}/select") |> json_response(200)

    refute Map.has_key?(body["data"]["branch_info"], "crm")
    refute inspect(body) =~ "super-secret-key"
  end

  test "inactive branches cannot be selected", %{conn: conn} do
    inactive = insert(:branch, is_active: false)

    assert %{"error" => "branch_not_found"} =
             conn |> post(~p"/client/branches/#{inactive.id}/select") |> json_response(404)
  end

  test "creates an order and ignores server-controlled fields", %{
    conn: conn,
    branch: branch,
    product: product
  } do
    conn = start_session(conn, branch)
    {conn, cart_id} = cart_with_product(conn, branch, product)
    foreign_client = insert(:client)

    params =
      order_params(branch, cart_id, %{
        "status" => "completed",
        "deleted_at" => "2026-01-01T00:00:00Z",
        "staff_id" => Ecto.UUID.generate(),
        "client_id" => foreign_client.id,
        "total_amount" => 1
      })

    data = conn |> post(~p"/client/orders", params) |> json_response(200) |> Map.fetch!("data")

    order = Repo.get!(Order, data["id"])
    assert order.status == :created
    assert order.deleted_at == nil
    assert order.staff_id == nil
    assert order.total_amount == 300
    assert order.client_id != foreign_client.id
    assert data["customer_phone"] == "+79990001122"
  end

  test "does not rename an existing client from a public order", %{
    conn: conn,
    branch: branch,
    product: product
  } do
    client = insert(:client, phone: "+79990001122", name: "Настоящее имя")

    conn = start_session(conn, branch)
    {conn, cart_id} = cart_with_product(conn, branch, product)

    conn
    |> post(~p"/client/orders", order_params(branch, cart_id, %{"customer_name" => "Хакер"}))
    |> json_response(200)

    assert Repo.reload!(client).name == "Настоящее имя"
  end

  test "a cart cannot be used from another session", %{
    conn: conn,
    branch: branch,
    product: product
  } do
    owner = start_session(conn, branch)
    {_owner, cart_id} = cart_with_product(owner, branch, product)

    stranger = build_conn() |> put_req_header("x-forwarded-for", "198.51.100.7")

    assert %{"error" => "cart_not_found"} =
             stranger
             |> post(~p"/client/cart/#{cart_id}/items/#{product.id}")
             |> json_response(404)

    assert %{"error" => "cart_not_found"} =
             stranger |> delete(~p"/client/cart/#{cart_id}/clear") |> json_response(404)

    assert %{"error" => "cart_not_found"} =
             stranger
             |> post(~p"/client/orders", order_params(branch, cart_id))
             |> json_response(422)
  end

  test "the same cart cannot be ordered twice", %{conn: conn, branch: branch, product: product} do
    conn = start_session(conn, branch)
    {conn, cart_id} = cart_with_product(conn, branch, product)

    first = post(conn, ~p"/client/orders", order_params(branch, cart_id))
    assert json_response(first, 200)

    second = post(recycle_with_headers(first), ~p"/client/orders", order_params(branch, cart_id))
    assert %{"error" => "cart_not_found"} = json_response(second, 422)

    assert Repo.aggregate(Order, :count) == 1
  end

  test "validation errors come back with field details", %{
    conn: conn,
    branch: branch,
    product: product
  } do
    conn = start_session(conn, branch)
    {conn, cart_id} = cart_with_product(conn, branch, product)

    body =
      conn
      |> post(~p"/client/orders", order_params(branch, cart_id, %{"customer_phone" => "123"}))
      |> json_response(422)

    assert body["error"] == "validation_failed"
    assert body["details"]["customer_phone"]
  end

  test "blocked clients cannot order", %{conn: conn, branch: branch, product: product} do
    insert(:client, phone: "+79990001122", status: :blocked)
    conn = start_session(conn, branch)
    {conn, cart_id} = cart_with_product(conn, branch, product)

    body =
      conn
      |> post(~p"/client/orders", order_params(branch, cart_id))
      |> json_response(422)

    assert body["error"] == "client_blocked"
  end

  describe "active orders" do
    test "lists orders of the current session only", %{
      conn: conn,
      branch: branch,
      product: product
    } do
      conn = start_session(conn, branch)
      {conn, cart_id} = cart_with_product(conn, branch, product)
      conn = post(conn, ~p"/client/orders", order_params(branch, cart_id))
      order_id = json_response(conn, 200)["data"]["id"]

      body =
        conn |> recycle_with_headers() |> get(~p"/client/orders/active") |> json_response(200)

      assert [%{"id" => ^order_id, "status" => "created", "items" => [_]}] = body["data"]

      other = build_conn() |> get(~p"/client/orders/active") |> json_response(200)
      assert other["data"] == []
    end

    test "hides finished and stale orders", %{conn: conn, branch: branch, product: product} do
      conn = start_session(conn, branch)
      {conn, cart_id} = cart_with_product(conn, branch, product)
      conn = post(conn, ~p"/client/orders", order_params(branch, cart_id))
      order = Repo.get!(Order, json_response(conn, 200)["data"]["id"])

      order |> Ecto.Changeset.change(status: :completed) |> Repo.update!()

      assert conn
             |> recycle_with_headers()
             |> get(~p"/client/orders/active")
             |> json_response(200) == %{"data" => []}

      stale = DateTime.add(DateTime.utc_now(:second), -8, :hour)
      order |> Ecto.Changeset.change(status: :ready, inserted_at: stale) |> Repo.update!()

      assert conn
             |> recycle_with_headers()
             |> get(~p"/client/orders/active")
             |> json_response(200) == %{"data" => []}
    end
  end

  describe "authenticated client" do
    defp authorize(conn, client),
      do:
        put_req_header(
          conn,
          "authorization",
          "Bearer " <> ClientToken.issue(client.id).access_token
        )

    test "orders are linked to the client and the address is remembered", %{
      conn: conn,
      branch: branch,
      product: product
    } do
      client = insert(:client, phone: "+79995556677")
      conn = start_session(conn, branch)
      {conn, cart_id} = cart_with_product(conn, branch, product)

      params =
        order_params(branch, cart_id, %{
          "fulfillment_type" => "delivery",
          "customer_phone" => "+79990001122",
          "address" => %{"street" => "Ленина", "house" => "1"}
        })

      data =
        conn |> authorize(client) |> post(~p"/client/orders", params) |> json_response(200)

      order_id = data["data"]["id"]
      assert Repo.get!(Order, order_id).client_id == client.id

      assert [%{street: "Ленина", house: "1"}] =
               Delivest.Identity.list_client_addresses(client.id)

      other_device =
        build_conn() |> put_req_header("x-forwarded-for", "203.0.113.9") |> authorize(client)

      assert [%{"id" => ^order_id}] =
               other_device
               |> get(~p"/client/orders/active")
               |> json_response(200)
               |> Map.fetch!("data")

      assert [%{"id" => ^order_id}] =
               other_device |> get(~p"/client/orders") |> json_response(200) |> Map.fetch!("data")
    end
  end

  test "order creation is rate limited per client IP", %{conn: conn} do
    statuses =
      for _ <- 1..11 do
        conn
        |> recycle_with_headers()
        |> post(~p"/client/orders", %{})
        |> Map.fetch!(:status)
      end

    assert Enum.take(statuses, 10) |> Enum.all?(&(&1 == 422))
    assert List.last(statuses) == 429
  end
end
