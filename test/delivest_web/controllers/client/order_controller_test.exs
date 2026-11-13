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

  defp keyed(conn, key), do: put_req_header(conn, "idempotency-key", key)

  test "keyed retry returns the original order after cart detach and branch pause", %{
    conn: conn,
    branch: branch,
    product: product
  } do
    conn = start_session(conn, branch)
    {conn, cart_id} = cart_with_product(conn, branch, product)
    key = Ecto.UUID.generate()
    params = order_params(branch, cart_id)

    first = conn |> keyed(key) |> post(~p"/client/orders", params) |> json_response(200)
    id = first["data"]["id"]

    staff = insert(:staff, role: insert(:role, permissions: ["orders.update"]))
    insert(:staff_branch, staff: staff, branch: branch)
    {:ok, _status} = Delivest.Intake.pause(staff, branch, 10, "перерыв")

    assert %{"data" => %{"id" => ^id}} =
             conn
             |> recycle_with_headers()
             |> keyed(key)
             |> post(~p"/client/orders", params)
             |> json_response(200)

    assert Repo.aggregate(Order, :count) == 1
  end

  test "keyed retry with changed accepted payload conflicts, ignored fields do not", %{
    conn: conn,
    branch: branch,
    product: product
  } do
    conn = start_session(conn, branch)
    {conn, cart_id} = cart_with_product(conn, branch, product)
    key = Ecto.UUID.generate()
    params = order_params(branch, cart_id)

    id =
      conn
      |> keyed(key)
      |> post(~p"/client/orders", params)
      |> json_response(200)
      |> get_in(["data", "id"])

    assert %{"data" => %{"id" => ^id}} =
             conn
             |> recycle_with_headers()
             |> keyed(key)
             |> post(~p"/client/orders", Map.put(params, "status", "completed"))
             |> json_response(200)

    assert %{"error" => "idempotency_conflict"} =
             conn
             |> recycle_with_headers()
             |> keyed(key)
             |> post(~p"/client/orders", Map.put(params, "comment", "другой"))
             |> json_response(409)

    assert Repo.aggregate(Order, :count) == 1
  end

  test "failed keyed attempt does not reserve the key", %{
    conn: conn,
    branch: branch,
    product: product
  } do
    conn = start_session(conn, branch)
    {conn, cart_id} = cart_with_product(conn, branch, product)
    key = Ecto.UUID.generate()
    invalid = order_params(branch, cart_id, %{"customer_phone" => "123"})

    assert %{"error" => "validation_failed"} =
             conn |> keyed(key) |> post(~p"/client/orders", invalid) |> json_response(422)

    assert Repo.aggregate(Order, :count) == 0

    assert %{"data" => %{"id" => _}} =
             conn
             |> recycle_with_headers()
             |> keyed(key)
             |> post(~p"/client/orders", order_params(branch, cart_id))
             |> json_response(200)
  end

  test "invalid key and invalid branch fail without a server error", %{conn: conn} do
    assert %{"error" => "invalid_idempotency_key"} =
             conn |> keyed("bad-key") |> post(~p"/client/orders", %{}) |> json_response(422)

    assert %{"error" => "branch_not_found"} =
             conn
             |> keyed(Ecto.UUID.generate())
             |> post(~p"/client/orders", %{"branch_id" => "not-a-uuid"})
             |> json_response(422)

    assert %{"error" => "invalid_idempotency_key"} =
             conn
             |> keyed("1234567890123456")
             |> post(~p"/client/orders", %{})
             |> json_response(422)
  end

  test "OpenAPI declares the exact UUID request header" do
    operation = DelivestWeb.Client.Order.OrderController.open_api_operation(:create)

    assert Enum.any?(operation.parameters, fn parameter ->
             parameter.name == "Idempotency-Key" and parameter.in == :header and
               parameter.schema.format == :uuid
           end)
  end

  test "checkout rejects a changed cart revision even when the total stays equal", %{
    conn: conn,
    branch: branch,
    product: product
  } do
    replacement = insert_branch_product(branch.id, price: 300)
    conn = start_session(conn, branch)
    {conn, cart_id} = cart_with_product(conn, branch, product)

    old_revision =
      conn
      |> get(~p"/client/cart?branch_id=#{branch.id}")
      |> json_response(200)
      |> get_in(["data", "revision"])

    assert is_binary(old_revision)

    conn =
      conn |> recycle_with_headers() |> delete(~p"/client/cart/#{cart_id}/items/#{product.id}")

    changed =
      conn
      |> recycle_with_headers()
      |> post(~p"/client/cart/#{cart_id}/items/#{replacement.id}")
      |> json_response(200)

    assert changed["data"]["total_amount"] == 300
    refute changed["data"]["revision"] == old_revision

    params = order_params(branch, cart_id, %{"cart_revision" => old_revision})

    assert %{"error" => "cart_changed"} =
             conn
             |> recycle_with_headers()
             |> post(~p"/client/orders", params)
             |> json_response(409)

    assert Repo.aggregate(Order, :count) == 0

    assert %{"data" => %{"id" => _}} =
             conn
             |> recycle_with_headers()
             |> post(~p"/client/orders", %{
               params
               | "cart_revision" => changed["data"]["revision"]
             })
             |> json_response(200)
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

  test "a paused branch does not take client orders", %{
    conn: conn,
    branch: branch,
    product: product
  } do
    conn = start_session(conn, branch)
    {conn, cart_id} = cart_with_product(conn, branch, product)

    staff = insert(:staff, role: insert(:role, permissions: ["orders.update"]))
    insert(:staff_branch, staff: staff, branch: branch)
    {:ok, _status} = Delivest.Intake.pause(staff, branch, 10, "нет курьеров")

    assert %{"error" => "branch_paused", "details" => %{"reason" => "нет курьеров"}} =
             conn |> post(~p"/client/orders", order_params(branch, cart_id)) |> json_response(422)
  end

  test "a payment method turned off at the branch is refused", %{
    conn: conn,
    branch: branch,
    product: product
  } do
    conn = start_session(conn, branch)
    {conn, cart_id} = cart_with_product(conn, branch, product)

    staff = insert(:staff, role: insert(:role, permissions: ["finance.update"]))
    insert(:staff_branch, staff: staff, branch: branch)
    {:ok, _branch} = Delivest.Identity.update_payments(staff, branch, %{"cash" => "false"})

    params = Map.put(order_params(branch, cart_id), "payment_method", "cash")

    assert %{"error" => "payment_method_disabled"} =
             conn |> post(~p"/client/orders", params) |> json_response(422)
  end

  test "the customer cancels an unaccepted order once", %{
    conn: conn,
    branch: branch,
    product: product
  } do
    conn = start_session(conn, branch)
    {conn, cart_id} = cart_with_product(conn, branch, product)
    data = conn |> post(~p"/client/orders", order_params(branch, cart_id)) |> json_response(200)
    id = data["data"]["id"]
    conn = recycle_with_headers(conn)

    assert [%{"can_cancel" => true}] =
             conn |> get(~p"/client/orders/active") |> json_response(200) |> Map.fetch!("data")

    assert %{"data" => %{"status" => "cancelled"}} =
             conn |> post(~p"/client/orders/#{id}/cancel") |> json_response(200)

    order = Repo.get!(Order, id)
    assert order.cancel_reason == :client

    assert %{"error" => "order_not_cancellable"} =
             conn |> post(~p"/client/orders/#{id}/cancel") |> json_response(422)
  end

  test "branch cancellation setting controls the active order and cancellation endpoint", %{
    conn: conn,
    branch: branch,
    product: product
  } do
    conn = start_session(conn, branch)
    {conn, cart_id} = cart_with_product(conn, branch, product)

    %{"data" => %{"id" => id}} =
      conn |> post(~p"/client/orders", order_params(branch, cart_id)) |> json_response(200)

    conn = recycle_with_headers(conn)
    info = Repo.get_by!(BranchInfo, branch_id: branch.id)
    assert info.fulfillment.client_cancellation

    other = insert(:branch)
    Repo.insert!(%BranchInfo{branch_id: other.id})

    {:ok, _} =
      info
      |> BranchInfo.changeset(%{fulfillment: %{client_cancellation: false}})
      |> Repo.update()

    assert [%{"can_cancel" => false}] =
             conn |> get(~p"/client/orders/active") |> json_response(200) |> Map.fetch!("data")

    assert %{"error" => "order_not_cancellable"} =
             conn |> post(~p"/client/orders/#{id}/cancel") |> json_response(422)

    assert Repo.get_by!(BranchInfo, branch_id: other.id).fulfillment.client_cancellation

    {:ok, _} =
      Repo.get_by!(BranchInfo, branch_id: branch.id)
      |> BranchInfo.changeset(%{fulfillment: %{client_cancellation: true}})
      |> Repo.update()

    assert [%{"can_cancel" => true}] =
             conn |> get(~p"/client/orders/active") |> json_response(200) |> Map.fetch!("data")
  end

  test "someone else's order is not found when cancelled", %{
    conn: conn,
    branch: branch,
    product: product
  } do
    conn = start_session(conn, branch)
    {conn, cart_id} = cart_with_product(conn, branch, product)
    data = conn |> post(~p"/client/orders", order_params(branch, cart_id)) |> json_response(200)

    stranger =
      build_conn()
      |> put_req_header("x-forwarded-for", "stranger-#{System.unique_integer([:positive])}")

    stranger = start_session(stranger, branch)

    assert %{"error" => "order_not_found"} =
             stranger
             |> post(~p"/client/orders/#{data["data"]["id"]}/cancel")
             |> json_response(404)
  end

  test "a guest can reopen only their own order", %{conn: conn, branch: branch, product: product} do
    conn = start_session(conn, branch)
    {conn, cart_id} = cart_with_product(conn, branch, product)
    order = conn |> post(~p"/client/orders", order_params(branch, cart_id)) |> json_response(200)
    id = order["data"]["id"]

    assert %{"data" => %{"id" => ^id, "total_amount" => 300, "items" => [_]}} =
             conn |> recycle_with_headers() |> get(~p"/client/orders/#{id}") |> json_response(200)

    stranger =
      build_conn()
      |> put_req_header("x-forwarded-for", "stranger-#{System.unique_integer([:positive])}")
      |> start_session(branch)

    assert %{"error" => "order_not_found"} =
             stranger |> get(~p"/client/orders/#{id}") |> json_response(404)

    assert %{"error" => "order_not_found"} =
             build_conn() |> get(~p"/client/orders/#{id}") |> json_response(404)
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

    test "switching clients in one session cannot expose or mutate the first client's order", %{
      conn: conn,
      branch: branch,
      product: product
    } do
      insert(:zvonok_settings)
      client_a = insert(:client, phone: "+79995550001")
      client_b = insert(:client, phone: "+79995550002")
      assert Delivest.Identity.client_auth_enabled?()
      conn = start_session(conn, branch)
      {conn, cart_id} = cart_with_product(conn, branch, product)

      assert %{"data" => %{"id" => _}} =
               conn |> authorize(client_a) |> get(~p"/client/me") |> json_response(200)

      order_id =
        conn
        |> authorize(client_a)
        |> post(
          ~p"/client/orders",
          order_params(branch, cart_id, %{"guest_session_access" => true})
        )
        |> json_response(200)
        |> get_in(["data", "id"])

      assert Repo.get!(Order, order_id).client_id == client_a.id
      refute Repo.get!(Order, order_id).guest_session_access
      guest = recycle_with_headers(conn)
      switched = authorize(guest, client_b)

      for actor <- [guest, switched] do
        assert %{"error" => "order_not_found"} =
                 actor |> get(~p"/client/orders/#{order_id}") |> json_response(404)

        assert actor |> get(~p"/client/orders/active") |> json_response(200) == %{"data" => []}

        assert %{"error" => "order_not_found"} =
                 actor |> post(~p"/client/orders/#{order_id}/cancel") |> json_response(404)

        assert %{"error" => "order_not_found"} =
                 actor |> post(~p"/client/orders/#{order_id}/pay") |> json_response(404)

        assert %{"error" => "order_not_found"} =
                 actor
                 |> post(~p"/client/orders/#{order_id}/push", %{})
                 |> json_response(404)
      end

      assert switched |> get(~p"/client/orders") |> json_response(200) == %{"data" => []}
      assert Repo.get!(Order, order_id).status == :created
    end

    test "guest order remains available to that session after sign-in", %{
      conn: conn,
      branch: branch,
      product: product
    } do
      insert(:zvonok_settings)
      client = insert(:client)
      conn = start_session(conn, branch)
      {conn, cart_id} = cart_with_product(conn, branch, product)

      order_id =
        conn
        |> post(~p"/client/orders", order_params(branch, cart_id))
        |> json_response(200)
        |> get_in(["data", "id"])

      assert Repo.get!(Order, order_id).guest_session_access
      signed_in = conn |> recycle_with_headers() |> authorize(client)

      assert %{"data" => %{"id" => ^order_id}} =
               signed_in |> get(~p"/client/orders/#{order_id}") |> json_response(200)

      assert [%{"id" => ^order_id}] =
               signed_in
               |> get(~p"/client/orders/active")
               |> json_response(200)
               |> Map.fetch!("data")

      other_session = build_conn() |> authorize(client)

      assert %{"error" => "order_not_found"} =
               other_session |> get(~p"/client/orders/#{order_id}") |> json_response(404)
    end

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

    test "a past order is repeated into the cart without unavailable products", %{
      conn: conn,
      branch: branch,
      product: product
    } do
      client = insert(:client, phone: "+79995556678")
      retired = insert_branch_product(branch.id, price: 100)
      conn = start_session(conn, branch)
      {conn, cart_id} = cart_with_product(conn, branch, product)
      conn = post(conn, ~p"/client/cart/#{cart_id}/items/#{product.id}")
      conn = post(recycle_with_headers(conn), ~p"/client/cart/#{cart_id}/items/#{retired.id}")

      order_id =
        conn
        |> recycle_with_headers()
        |> authorize(client)
        |> post(~p"/client/orders", order_params(branch, cart_id))
        |> json_response(200)
        |> get_in(["data", "id"])

      retired |> Ecto.Changeset.change(is_active: false) |> Repo.update!()

      conn = conn |> recycle_with_headers() |> get(~p"/client/cart?branch_id=#{branch.id}")
      new_cart_id = json_response(conn, 200)["data"]["id"]

      assert %{"items" => [%{"product_id" => product_id, "quantity" => 2}]} =
               conn
               |> recycle_with_headers()
               |> authorize(client)
               |> post(~p"/client/cart/#{new_cart_id}/repeat/#{order_id}")
               |> json_response(200)
               |> Map.fetch!("data")

      assert product_id == product.id

      assert %{"error" => "order_not_found"} =
               conn
               |> recycle_with_headers()
               |> authorize(insert(:client, phone: "+79995556679"))
               |> post(~p"/client/cart/#{new_cart_id}/repeat/#{order_id}")
               |> json_response(404)
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

  test "a phone number alone cannot spend a client's stars", %{
    conn: conn,
    branch: branch,
    product: product
  } do
    Repo.get_by!(BranchInfo, branch_id: branch.id)
    |> BranchInfo.changeset(%{"loyalty" => %{"enabled" => true, "shop_enabled" => true}})
    |> Repo.update!()

    Cachex.clear(:branch_cache)
    product |> Ecto.Changeset.change(stars_price: 1) |> Repo.update!()
    conn = start_session(conn, branch)
    {conn, cart_id} = cart_with_product(conn, branch, product)
    {:ok, _, _} = Delivest.Oms.Carts.add_star_item(cart_id, product.id)
    conn = post(conn, ~p"/client/orders", order_params(branch, cart_id))
    assert json_response(conn, 422)["error"] == "points_unavailable"
  end
end
