defmodule DelivestWeb.Client.SavedPaymentMethodsTest do
  use DelivestWeb.ConnCase, async: false

  import Ecto.Query
  import Delivest.Factory

  alias Delivest.Integrations.{Health, Yookassa}
  alias Delivest.Identity.Branch.{BranchInfo, PaymentSettings}
  alias Delivest.Oms.Order
  alias Delivest.Oms
  alias Delivest.Payments.{Payment, Refund, SavedMethods, SavedPaymentMethod}
  alias Delivest.Repo
  alias DelivestWeb.ClientToken

  setup %{conn: conn} do
    conn =
      put_req_header(
        conn,
        "x-forwarded-for",
        "saved-payments-#{System.unique_integer([:positive])}"
      )

    branch = insert(:branch, is_active: true)
    Repo.insert!(%BranchInfo{branch_id: branch.id, payments: %PaymentSettings{online: true}})

    Repo.insert!(%Yookassa.Settings{
      shop_id: "506751",
      secret_key: "k",
      webhook_token: "hook",
      saved_payment_methods_enabled: true
    })

    Repo.insert!(%Health.Status{
      provider: "yookassa",
      status: :ok,
      checked_at: DateTime.utc_now()
    })

    client = insert(:client)
    other = insert(:client)
    product = insert_branch_product(branch.id, price: 300)
    access = ClientToken.issue(client.id).access_token
    conn = conn |> put_req_header("authorization", "Bearer " <> access)
    conn = post(conn, ~p"/client/branches/#{branch.id}/select")
    conn = get(recycle_with_ip(conn), ~p"/client/cart?branch_id=#{branch.id}")
    cart_id = json_response(conn, 200)["data"]["id"]
    conn = post(recycle_with_ip(conn), ~p"/client/cart/#{cart_id}/items/#{product.id}")
    %{conn: recycle_with_ip(conn), branch: branch, client: client, other: other, cart_id: cart_id}
  end

  defp recycle_with_ip(conn) do
    ip = get_req_header(conn, "x-forwarded-for")
    conn = recycle(conn)

    case ip do
      [value] -> put_req_header(conn, "x-forwarded-for", value)
      _ -> conn
    end
  end

  defp attrs(context) do
    %{
      "cart_id" => context.cart_id,
      "branch_id" => context.branch.id,
      "fulfillment_type" => "pickup",
      "payment_method" => "online",
      "expected_total" => 300,
      "confirmed_payment_total" => 300
    }
  end

  defp method(client_id, shop_id \\ "506751") do
    Repo.insert!(%SavedPaymentMethod{
      client_id: client_id,
      shop_id: shop_id,
      provider_method_id: Ecto.UUID.generate(),
      type: "bank_card",
      title: "Visa",
      last4: "4242"
    })
  end

  test "methods are private and tombstone prevents late provider replay", context do
    %{conn: conn, client: client, other: other} = context
    saved = method(client.id)
    method(other.id)
    method(client.id, "other-shop")

    assert %{"data" => [%{"id" => id, "title" => "Visa"}]} =
             conn |> get(~p"/client/payment-methods") |> json_response(200)

    assert id == saved.id

    refute json_response(conn |> get(~p"/client/payment-methods"), 200) |> inspect() =~
             saved.provider_method_id

    assert conn |> delete(~p"/client/payment-methods/#{saved.id}") |> response(204)
    assert %{"data" => []} = conn |> get(~p"/client/payment-methods") |> json_response(200)

    assert :ok =
             SavedMethods.save_from_provider(client.id, "506751", %{
               "id" => saved.provider_method_id,
               "saved" => true,
               "type" => "bank_card",
               "card" => %{"last4" => "4242"}
             })

    assert %{"data" => []} = conn |> get(~p"/client/payment-methods") |> json_response(200)

    deleted_at = Repo.get!(SavedPaymentMethod, saved.id).deleted_at
    renewed_consent = deleted_at |> DateTime.add(1, :microsecond) |> DateTime.to_iso8601()

    assert :ok =
             SavedMethods.save_from_provider(
               client.id,
               "506751",
               %{"id" => saved.provider_method_id, "saved" => true, "type" => "bank_card"},
               renewed_consent
             )

    assert %{"data" => [%{"id" => ^id}]} =
             conn |> get(~p"/client/payment-methods") |> json_response(200)
  end

  test "foreign method and changed amount are rejected before provider call", context do
    %{conn: conn, other: other} = context
    foreign = method(other.id)
    attrs = Map.put(attrs(context), "saved_payment_method_id", foreign.id)

    assert %{"error" => "saved_payment_method_not_found"} =
             conn |> post(~p"/client/orders", attrs) |> json_response(422)

    assert Repo.aggregate(Order, :count) == 0

    own = method(context.client.id)

    attrs =
      attrs
      |> Map.put("saved_payment_method_id", own.id)
      |> Map.put("confirmed_payment_total", 301)

    assert %{"error" => "payment_amount_changed"} =
             conn |> post(~p"/client/orders", attrs) |> json_response(422)

    assert Repo.aggregate(Order, :count) == 0
  end

  test "canceled saved attempt can use ordinary payment on the same order", context do
    saved = method(context.client.id)
    test_pid = self()

    Req.Test.stub(Delivest.HTTP.Client, fn req ->
      {:ok, body, req} = Plug.Conn.read_body(req)
      body = if body == "", do: %{}, else: Jason.decode!(body)
      send(test_pid, {:provider, req.method, req.request_path, body})

      response =
        case {req.method, req.request_path} do
          {"POST", "/v3/payments"} when is_map_key(body, "payment_method_id") ->
            %{
              "id" => "saved-attempt",
              "status" => "canceled",
              "amount" => %{"value" => "3.00", "currency" => "RUB"},
              "recipient" => %{"account_id" => "506751"}
            }

          {"GET", "/v3/payments/saved-attempt"} ->
            %{
              "id" => "saved-attempt",
              "status" => "canceled",
              "recipient" => %{"account_id" => "506751"}
            }

          {"POST", "/v3/payments"} ->
            %{
              "id" => "ordinary-attempt",
              "status" => "pending",
              "recipient" => %{"account_id" => "506751"},
              "confirmation" => %{"confirmation_url" => "https://yoomoney.ru/pay"}
            }
        end

      Req.Test.json(req, response)
    end)

    attrs = attrs(context) |> Map.put("saved_payment_method_id", saved.id)
    body = context.conn |> post(~p"/client/orders", attrs) |> json_response(200)
    order_id = body["data"]["id"]
    assert body["data"]["saved_payment_fallback_available"] == true
    assert_receive {:provider, "POST", "/v3/payments", %{"payment_method_id" => provider_id}}
    assert provider_id == saved.provider_method_id
    assert Repo.get!(Order, order_id).awaiting_payment

    response =
      context.conn
      |> post(~p"/client/orders/#{order_id}/pay", %{"fallback_to_new_method" => true})
      |> json_response(200)

    assert response["data"]["confirmation_url"] == "https://yoomoney.ru/pay"
    assert Repo.aggregate(Order, :count) == 1
    assert Repo.aggregate(Payment, :count) == 2

    assert [%Payment{details: %{"saved_method_fallback" => true, "shop_id" => "506751"}}] =
             Repo.all(from p in Payment, where: p.external_id == "ordinary-attempt")

    assert_receive {:provider, "POST", "/v3/payments", body}
    refute Map.has_key?(body, "payment_method_id")
  end

  test "guest cannot opt in and a saved method belongs to this shop", context do
    guest = context.conn |> recycle_with_ip() |> delete_req_header("authorization")

    assert %{"error" => "client_auth_required"} =
             guest
             |> post(~p"/client/orders", Map.put(attrs(context), "save_payment_method", true))
             |> json_response(401)

    foreign_shop = method(context.client.id, "another-shop")

    assert %{"error" => "saved_payment_method_not_found"} =
             context.conn
             |> post(
               ~p"/client/orders",
               Map.put(attrs(context), "saved_payment_method_id", foreign_shop.id)
             )
             |> json_response(422)

    assert Repo.aggregate(Order, :count) == 0
  end

  test "save requires provider confirmation and matching recipient", context do
    test_pid = self()

    Req.Test.stub(Delivest.HTTP.Client, fn req ->
      send(test_pid, {:provider, req.method, req.request_path})

      response =
        case {req.method, req.request_path} do
          {"POST", "/v3/payments"} ->
            %{
              "id" => "opt-in",
              "status" => "pending",
              "amount" => %{"value" => "3.00", "currency" => "RUB"},
              "recipient" => %{"account_id" => "506751"},
              "payment_method" => %{
                "id" => "provider-card",
                "type" => "bank_card",
                "saved" => false
              },
              "confirmation" => %{"confirmation_url" => "https://yoomoney.ru/pay"}
            }

          {"GET", "/v3/payments/opt-in"} ->
            %{
              "id" => "opt-in",
              "status" => "pending",
              "amount" => %{"value" => "3.00", "currency" => "RUB"},
              "recipient" => %{"account_id" => "506751"},
              "payment_method" => %{
                "id" => "provider-card",
                "type" => "bank_card",
                "saved" => true,
                "card" => %{"last4" => "4242", "card_type" => "Visa"}
              }
            }
        end

      Req.Test.json(req, response)
    end)

    attrs = Map.put(attrs(context), "save_payment_method", true)

    assert %{"data" => %{"payment" => %{"confirmation_url" => "https://yoomoney.ru/pay"}}} =
             context.conn |> post(~p"/client/orders", attrs) |> json_response(200)

    assert_receive {:provider, "POST", "/v3/payments"}
    assert SavedMethods.list(context.client.id) == []
    assert {:ok, :unchanged} = Delivest.Payments.Online.sync("opt-in")
    assert [%SavedPaymentMethod{last4: "4242"}] = SavedMethods.list(context.client.id)
  end

  test "provider recipient mismatch cannot activate an opt-in payment", context do
    Req.Test.stub(Delivest.HTTP.Client, fn req ->
      Req.Test.json(req, %{
        "id" => "wrong-shop",
        "status" => "waiting_for_capture",
        "amount" => %{"value" => "3.00", "currency" => "RUB"},
        "recipient" => %{"account_id" => "other-shop"},
        "payment_method" => %{"id" => "provider-card", "saved" => true}
      })
    end)

    assert %{"error" => "payment_unavailable"} =
             context.conn
             |> post(~p"/client/orders", Map.put(attrs(context), "save_payment_method", true))
             |> json_response(502)

    assert SavedMethods.list(context.client.id) == []
    assert [%Payment{external_id: nil}] = Repo.all(Payment)
  end

  test "saved method supports immediate authorization without redirect", context do
    saved = method(context.client.id)
    test_pid = self()

    Req.Test.stub(Delivest.HTTP.Client, fn req ->
      {:ok, raw, req} = Plug.Conn.read_body(req)
      send(test_pid, Jason.decode!(raw))

      Req.Test.json(req, %{
        "id" => "immediate-hold",
        "status" => "waiting_for_capture",
        "amount" => %{"value" => "3.00", "currency" => "RUB"},
        "recipient" => %{"account_id" => "506751"}
      })
    end)

    attrs = attrs(context) |> Map.put("saved_payment_method_id", saved.id)
    body = context.conn |> post(~p"/client/orders", attrs) |> json_response(200)
    assert body["data"]["awaiting_payment"] == true

    assert_receive %{
      "payment_method_id" => provider_id,
      "confirmation" => %{"type" => "redirect"}
    }

    assert provider_id == saved.provider_method_id
    assert Repo.get!(Order, body["data"]["id"]).awaiting_payment == false
  end

  test "timeout followed by deletion does not permit another charge", context do
    saved = method(context.client.id)
    Req.Test.stub(Delivest.HTTP.Client, &Req.Test.transport_error(&1, :timeout))
    attrs = attrs(context) |> Map.put("saved_payment_method_id", saved.id)
    key = Ecto.UUID.generate()
    conn = put_req_header(context.conn, "idempotency-key", key)

    assert %{"error" => "payment_unavailable"} =
             conn |> post(~p"/client/orders", attrs) |> json_response(502)

    assert [%Payment{external_id: nil, details: %{"provider_attempted_at" => _}}] =
             Repo.all(Payment)

    assert {:ok, _} = SavedMethods.delete(context.client.id, saved.id)

    assert %{"error" => "payment_unavailable"} =
             conn
             |> recycle_with_ip()
             |> put_req_header("idempotency-key", key)
             |> post(~p"/client/orders", attrs)
             |> json_response(502)

    assert [%Payment{status: :pending, external_id: nil}] = Repo.all(Payment)
    assert Repo.aggregate(Order, :count) == 1
  end

  test "deletion before first attempt opens fallback without provider call", context do
    saved = method(context.client.id)

    payment_context = %{
      "saved_payment_method_id" => saved.id,
      "client_id" => context.client.id,
      "shop_id" => "506751"
    }

    assert {:ok, order} =
             Oms.create_order(
               %{
                 "cart_id" => context.cart_id,
                 "branch_id" => context.branch.id,
                 "client_id" => context.client.id,
                 "customer_phone" => context.client.phone,
                 "fulfillment_type" => "pickup",
                 "payment_method" => "online"
               },
               online: true,
               payment_context: payment_context
             )

    assert {:ok, _} = SavedMethods.delete(context.client.id, saved.id)
    pay_conn = context.conn |> post(~p"/client/orders/#{order.id}/pay")
    assert response(pay_conn, 204) == ""

    assert [
             %Payment{
               status: :cancelled,
               external_id: nil,
               details: %{"no_remote_attempt" => true}
             }
           ] = Repo.all(Payment)

    assert SavedMethods.fallback_available?(order.id)

    test_pid = self()

    Req.Test.stub(Delivest.HTTP.Client, fn req ->
      send(test_pid, {req.method, req.request_path})

      Req.Test.json(req, %{
        "id" => "fallback-after-local-delete",
        "status" => "pending",
        "recipient" => %{"account_id" => "506751"},
        "confirmation" => %{"confirmation_url" => "https://yoomoney.ru/pay"}
      })
    end)

    assert {:ok, "https://yoomoney.ru/pay"} = Delivest.Payments.Online.fallback(order)
    assert_receive {"POST", "/v3/payments"}
    refute_receive {"GET", _}
  end

  test "saved method can require redirect confirmation", context do
    saved = method(context.client.id)

    Req.Test.stub(Delivest.HTTP.Client, fn req ->
      Req.Test.json(req, %{
        "id" => "saved-redirect",
        "status" => "pending",
        "recipient" => %{"account_id" => "506751"},
        "confirmation" => %{"confirmation_url" => "https://yoomoney.ru/3ds"}
      })
    end)

    body =
      context.conn
      |> post(~p"/client/orders", Map.put(attrs(context), "saved_payment_method_id", saved.id))
      |> json_response(200)

    assert body["data"]["payment"]["confirmation_url"] == "https://yoomoney.ru/3ds"
  end

  test "aged or changed-shop fallback never retries its provider POST", context do
    assert {:ok, order} =
             Oms.create_order(
               %{
                 "cart_id" => context.cart_id,
                 "branch_id" => context.branch.id,
                 "client_id" => context.client.id,
                 "customer_phone" => context.client.phone,
                 "fulfillment_type" => "pickup",
                 "payment_method" => "online"
               },
               online: true
             )

    payment = Repo.get_by!(Payment, order_id: order.id)
    old = DateTime.add(DateTime.utc_now(:second), -90_000, :second)

    payment
    |> Ecto.Changeset.change(
      details: %{"saved_method_fallback" => true, "shop_id" => "506751"},
      inserted_at: old
    )
    |> Repo.update!()

    Req.Test.stub(Delivest.HTTP.Client, fn _req -> flunk("provider POST must not be called") end)
    assert {:error, :payment_outcome_unknown} = Delivest.Payments.Online.start(order)

    payment |> Ecto.Changeset.change(inserted_at: DateTime.utc_now(:second)) |> Repo.update!()
    settings = Yookassa.get_settings()
    settings |> Ecto.Changeset.change(shop_id: "999999") |> Repo.update!()
    assert {:error, :saved_payment_shop_changed} = Delivest.Payments.Online.start(order)
  end

  test "a refund still uses the payment after its saved method is deleted", context do
    saved = method(context.client.id)

    payment_context = %{
      "saved_payment_method_id" => saved.id,
      "client_id" => context.client.id,
      "shop_id" => "506751"
    }

    assert {:ok, order} =
             Oms.create_order(
               %{
                 "cart_id" => context.cart_id,
                 "branch_id" => context.branch.id,
                 "client_id" => context.client.id,
                 "customer_phone" => context.client.phone,
                 "fulfillment_type" => "pickup",
                 "payment_method" => "online"
               },
               online: true,
               payment_context: payment_context
             )

    payment = Repo.get_by!(Payment, order_id: order.id)

    payment =
      payment
      |> Ecto.Changeset.change(status: :paid, external_id: "paid-provider-id")
      |> Repo.update!()

    assert {:ok, _} = SavedMethods.delete(context.client.id, saved.id)

    refund =
      %Refund{
        payment_id: payment.id,
        order_id: order.id,
        amount: 300,
        reason: "client requested",
        status: :pending,
        provider: "yookassa"
      }
      |> Repo.insert!()
      |> Repo.preload(:payment)

    test_pid = self()

    Req.Test.stub(Delivest.HTTP.Client, fn req ->
      {:ok, raw, req} = Plug.Conn.read_body(req)
      send(test_pid, Jason.decode!(raw))

      Req.Test.json(req, %{
        "id" => "refund-after-delete",
        "status" => "pending",
        "payment_id" => "paid-provider-id",
        "amount" => %{"value" => "3.00", "currency" => "RUB"}
      })
    end)

    assert :ok = Delivest.Payments.Online.send_refund(refund)
    assert_receive %{"payment_id" => "paid-provider-id"}
  end

  test "disabled gate blocks new saved charges but keeps an existing payment link", context do
    saved = method(context.client.id)
    test_pid = self()

    Req.Test.stub(Delivest.HTTP.Client, fn req ->
      send(test_pid, :posted)

      Req.Test.json(req, %{
        "id" => "pending-with-link",
        "status" => "pending",
        "recipient" => %{"account_id" => "506751"},
        "confirmation" => %{"confirmation_url" => "https://yoomoney.ru/pay"}
      })
    end)

    key = Ecto.UUID.generate()
    attrs = attrs(context) |> Map.put("saved_payment_method_id", saved.id)
    conn = put_req_header(context.conn, "idempotency-key", key)
    first = conn |> post(~p"/client/orders", attrs) |> json_response(200)
    assert_receive :posted
    settings = Yookassa.get_settings()
    settings |> Ecto.Changeset.change(saved_payment_methods_enabled: false) |> Repo.update!()

    replay =
      conn
      |> recycle_with_ip()
      |> put_req_header("idempotency-key", key)
      |> post(~p"/client/orders", attrs)
      |> json_response(200)

    assert replay["data"]["id"] == first["data"]["id"]
    refute_received :posted

    assert %{"error" => "saved_payment_methods_disabled"} =
             context.conn
             |> post(
               ~p"/client/orders",
               Map.put(attrs, "save_payment_method", true)
               |> Map.delete("saved_payment_method_id")
             )
             |> json_response(422)
  end
end
