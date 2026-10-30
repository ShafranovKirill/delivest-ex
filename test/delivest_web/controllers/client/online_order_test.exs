defmodule DelivestWeb.Client.OnlineOrderTest do
  use DelivestWeb.ConnCase, async: true

  import Ecto.Query
  import Delivest.Factory

  alias Delivest.Events.Event
  alias Delivest.Identity.Branch.{BranchInfo, PaymentSettings}
  alias Delivest.Integrations.{Health, Yookassa}
  alias Delivest.Oms.{Order, OrderFlow}
  alias Delivest.Payments
  alias Delivest.Repo

  setup %{conn: conn} do
    branch = insert(:branch, is_active: true)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      payments: %PaymentSettings{online: true}
    })

    Repo.insert!(%Yookassa.Settings{
      shop_id: "506751",
      secret_key: "k",
      webhook_token: "hook-token"
    })

    Repo.insert!(%Health.Status{
      provider: "yookassa",
      status: :ok,
      checked_at: DateTime.utc_now()
    })

    product = insert_branch_product(branch.id, price: 300)
    ip = "client-#{System.unique_integer([:positive])}"
    conn = put_req_header(conn, "x-forwarded-for", "spoofed, #{ip}")

    conn = post(conn, ~p"/client/branches/#{branch.id}/select")

    assert json_response(conn, 200)["data"]["branch_info"]["payment_methods"]
           |> Enum.member?("online")

    conn = recycle_with_headers(conn)

    conn = get(conn, ~p"/client/cart?branch_id=#{branch.id}")
    cart_id = json_response(conn, 200)["data"]["id"]
    conn = post(recycle_with_headers(conn), ~p"/client/cart/#{cart_id}/items/#{product.id}")
    assert json_response(conn, 200)

    %{conn: recycle_with_headers(conn), branch: branch, cart_id: cart_id}
  end

  defp recycle_with_headers(conn) do
    forwarded = get_req_header(conn, "x-forwarded-for")
    conn |> recycle() |> put_req_header("x-forwarded-for", Enum.join(forwarded, ","))
  end

  defp params(branch, cart_id) do
    %{
      "cart_id" => cart_id,
      "branch_id" => branch.id,
      "fulfillment_type" => "pickup",
      "payment_method" => "online",
      "customer_phone" => "+79990001122",
      "customer_name" => "Иван"
    }
  end

  defp stub_yookassa(test_pid) do
    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:yookassa, conn.request_path, conn.req_headers, Jason.decode!(body)})

      Req.Test.json(conn, %{
        "id" => "2d9c4d8e-000f-5000-9000-1f9a3b7c1e11",
        "status" => "pending",
        "confirmation" => %{
          "type" => "redirect",
          "confirmation_url" => "https://yoomoney.ru/checkout/payments/v2/contract?orderId=2d9c"
        }
      })
    end)
  end

  test "an online order waits for the hold and returns the payment page", %{
    conn: conn,
    branch: branch,
    cart_id: cart_id
  } do
    stub_yookassa(self())

    body = conn |> post(~p"/client/orders", params(branch, cart_id)) |> json_response(200)

    assert %{
             "payment_method" => "online",
             "awaiting_payment" => true,
             "status" => "created",
             "payment" => %{"confirmation_url" => "https://yoomoney.ru/checkout" <> _}
           } = body["data"]

    assert_received {:yookassa, path, headers, request}
    assert String.ends_with?(path, "/payments")
    assert request["capture"] == false
    assert request["amount"] == %{"value" => "3.00", "currency" => "RUB"}
    assert request["confirmation"]["type"] == "redirect"
    assert request["confirmation"]["return_url"] =~ body["data"]["id"]

    order = Repo.get!(Order, body["data"]["id"])
    [payment] = Payments.list(order.id)
    assert {"idempotence-key", payment.id} in headers
    assert %{method: :online, status: :pending, provider: "yookassa", amount: 300} = payment
    assert payment.external_id == "2d9c4d8e-000f-5000-9000-1f9a3b7c1e11"

    refute Repo.exists?(
             from(e in Event, where: e.type == "order.created" and e.aggregate_id == ^order.id)
           )
  end

  test "the operator cannot take an unpaid order into work", %{
    conn: conn,
    branch: branch,
    cart_id: cart_id
  } do
    stub_yookassa(self())
    body = conn |> post(~p"/client/orders", params(branch, cart_id)) |> json_response(200)
    order = Repo.get!(Order, body["data"]["id"])

    assert {:ignored, :awaiting_payment} = OrderFlow.steps(order, :accepted, :crm)

    assert {:error, :awaiting_payment} =
             OrderFlow.steps(order, :accepted, {:staff, insert(:staff)})

    assert {:ok, [{:created, :cancelled}]} = OrderFlow.steps(order, :cancelled, :client)
  end

  test "the customer cancels an order that is not paid yet", %{
    conn: conn,
    branch: branch,
    cart_id: cart_id
  } do
    stub_yookassa(self())
    body = conn |> post(~p"/client/orders", params(branch, cart_id)) |> json_response(200)
    id = body["data"]["id"]

    conn = recycle_with_headers(conn)

    assert %{"data" => %{"status" => "cancelled"}} =
             conn |> post(~p"/client/orders/#{id}/cancel") |> json_response(200)

    assert [%{status: :cancelled}] = Payments.list(id)
  end

  test "a failed payment request cancels the order and asks for another method", %{
    conn: conn,
    branch: branch,
    cart_id: cart_id
  } do
    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"type" => "error"})
    end)

    assert %{"error" => "payment_unavailable"} =
             conn |> post(~p"/client/orders", params(branch, cart_id)) |> json_response(502)

    assert [%Order{status: :cancelled, cancel_reason: :not_paid}] = Repo.all(Order)
  end

  describe "yookassa webhook" do
    setup %{conn: conn, branch: branch, cart_id: cart_id} do
      stub_yookassa(self())
      body = conn |> post(~p"/client/orders", params(branch, cart_id)) |> json_response(200)
      order = Repo.get!(Order, body["data"]["id"])
      [payment] = Payments.list(order.id)
      token = Yookassa.get_settings().webhook_token

      %{order: order, payment: payment, token: token, external_id: payment.external_id}
    end

    defp remote(external_id, status, value \\ "3.00") do
      Req.Test.stub(Delivest.HTTP.Client, fn conn ->
        Req.Test.json(conn, %{
          "id" => external_id,
          "status" => status,
          "amount" => %{"value" => value, "currency" => "RUB"}
        })
      end)
    end

    defp notify(conn, token, event, external_id) do
      conn =
        post(conn, "/integrations/yookassa/#{token}", %{
          "event" => event,
          "object" => %{"id" => external_id}
        })

      assert json_response(conn, 200)
      Oban.drain_queue(queue: :default, with_safety: false)
    end

    test "the hold releases the order to the kitchen and the crm", ctx do
      remote(ctx.external_id, "waiting_for_capture")
      notify(ctx.conn, ctx.token, "payment.waiting_for_capture", ctx.external_id)

      order = Repo.get!(Order, ctx.order.id)
      refute order.awaiting_payment
      assert [%{status: :authorized}] = Payments.list(order.id)

      assert Repo.exists?(
               from(e in Event, where: e.type == "order.created" and e.aggregate_id == ^order.id)
             )
    end

    test "a repeated notification changes nothing", ctx do
      remote(ctx.external_id, "waiting_for_capture")
      notify(ctx.conn, ctx.token, "payment.waiting_for_capture", ctx.external_id)
      notify(ctx.conn, ctx.token, "payment.waiting_for_capture", ctx.external_id)

      count =
        Repo.aggregate(
          from(e in Event, where: e.type == "order.created" and e.aggregate_id == ^ctx.order.id),
          :count
        )

      assert count == 1
    end

    test "an amount that differs from the hold is not accepted", ctx do
      remote(ctx.external_id, "waiting_for_capture", "1.00")
      notify(ctx.conn, ctx.token, "payment.waiting_for_capture", ctx.external_id)

      assert Repo.get!(Order, ctx.order.id).awaiting_payment
      assert [%{status: :pending}] = Payments.list(ctx.order.id)
    end

    test "a canceled payment of an unpaid order cancels the order", ctx do
      remote(ctx.external_id, "canceled")
      notify(ctx.conn, ctx.token, "payment.canceled", ctx.external_id)

      assert %{status: :cancelled, cancel_reason: :not_paid} = Repo.get!(Order, ctx.order.id)
      assert [%{status: :cancelled}] = Payments.list(ctx.order.id)
    end

    test "a wrong token is turned away", ctx do
      conn =
        post(ctx.conn, "/integrations/yookassa/wrong", %{
          "event" => "payment.succeeded",
          "object" => %{"id" => "x"}
        })

      assert json_response(conn, 404)
    end

    test "the poller picks up a payment the webhook missed", ctx do
      remote(ctx.external_id, "waiting_for_capture")
      later = DateTime.add(DateTime.utc_now(), 300, :second)

      assert [{_id, {:ok, :authorized}}] = Delivest.Payments.Online.PollWorker.poll(later)
      refute Repo.get!(Order, ctx.order.id).awaiting_payment
    end
  end
end
