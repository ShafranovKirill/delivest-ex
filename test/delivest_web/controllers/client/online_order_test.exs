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

      send(
        test_pid,
        {:yookassa, conn.request_path, conn.req_headers,
         if(body == "", do: %{}, else: Jason.decode!(body))}
      )

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

  describe "capture and release" do
    setup %{conn: conn, branch: branch, cart_id: cart_id} do
      stub_yookassa(self())
      body = conn |> post(~p"/client/orders", params(branch, cart_id)) |> json_response(200)
      order = Repo.get!(Order, body["data"]["id"])
      [payment] = Payments.list(order.id)

      %{conn: conn, order: order, payment: payment, id: payment.external_id}
    end

    defp drain do
      Oban.drain_queue(queue: :default, with_safety: false)
      Oban.drain_queue(queue: :events, with_safety: false)
    end

    defp remote_api(test_pid, id, status, refund_amount \\ "3.00") do
      Req.Test.stub(Delivest.HTTP.Client, fn conn ->
        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:remote, conn.method, conn.request_path, conn.req_headers, raw})

        cond do
          String.ends_with?(conn.request_path, "/refunds") ->
            Req.Test.json(conn, %{
              "id" => "refund-1",
              "status" => "pending",
              "amount" => %{"value" => refund_amount, "currency" => "RUB"}
            })

          String.contains?(conn.request_path, "/refunds/") ->
            Req.Test.json(conn, %{
              "id" => "refund-1",
              "status" => "succeeded",
              "amount" => %{"value" => refund_amount, "currency" => "RUB"}
            })

          true ->
            remote_status =
              cond do
                String.ends_with?(conn.request_path, "/capture") -> "succeeded"
                String.ends_with?(conn.request_path, "/cancel") -> "canceled"
                true -> status
              end

            Req.Test.json(conn, %{
              "id" => id,
              "status" => remote_status,
              "amount" => %{"value" => "3.00", "currency" => "RUB"}
            })
        end
      end)
    end

    defp hold(ctx) do
      remote_api(self(), ctx.id, "waiting_for_capture")
      {:ok, _} = Delivest.Payments.Online.sync(ctx.id)
      Repo.get!(Order, ctx.order.id)
    end

    test "accepting the order captures the hold", ctx do
      order = hold(ctx)
      staff = insert(:staff, role: insert(:role, permissions: ["admin"]))

      insert(:staff_branch,
        staff: staff,
        branch: Repo.get!(Delivest.Identity.Branch, order.branch_id)
      )

      assert {:ok, _} = Delivest.Oms.Orders.advance_order(order, :accepted, {:staff, staff})
      drain()

      assert_received {:remote, "POST", path, headers, _raw}
      assert String.ends_with?(path, "/payments/#{ctx.id}/capture")
      assert {"idempotence-key", ctx.payment.id <> ":capture"} in headers
      assert [%{status: :paid, paid_at: %DateTime{}}] = Payments.list(order.id)
    end

    test "cancelling the order releases the hold", ctx do
      order = hold(ctx)
      staff = insert(:staff, role: insert(:role, permissions: ["admin"]))

      insert(:staff_branch,
        staff: staff,
        branch: Repo.get!(Delivest.Identity.Branch, order.branch_id)
      )

      assert {:ok, _} =
               Delivest.Oms.Orders.cancel_order(order, {:staff, staff}, %{
                 "cancel_reason" => "other"
               })

      drain()

      assert_received {:remote, "POST", path, _headers, _raw}
      assert String.ends_with?(path, "/cancel")
      assert [%{status: :cancelled, details: %{"released" => true}}] = Payments.list(order.id)
    end

    test "a hold that arrives after the customer cancelled is released", ctx do
      {:ok, _} = Delivest.Oms.Orders.cancel_by_client(ctx.order.session_id, nil, ctx.order.id)
      drain()
      refute_received {:remote, _, _, _, _}

      remote_api(self(), ctx.id, "waiting_for_capture")
      assert {:ok, _} = Delivest.Payments.Online.sync(ctx.id)

      assert_received {:remote, "POST", path, _headers, _raw}
      assert String.ends_with?(path, "/cancel")
    end

    test "a hold that expires cancels the active order", ctx do
      order = hold(ctx)
      remote_api(self(), ctx.id, "canceled")
      assert {:ok, :cancelled} = Delivest.Payments.Online.sync(ctx.id)

      assert %{status: :cancelled, cancel_reason: :not_paid} = Repo.get!(Order, order.id)
    end

    test "the no-call option accepts a paid order and captures it", ctx do
      staff = insert(:staff, role: insert(:role, permissions: ["finance.update"]))
      branch = Repo.get!(Delivest.Identity.Branch, ctx.order.branch_id)
      insert(:staff_branch, staff: staff, branch: branch)

      {:ok, _} =
        Delivest.Identity.update_payments(staff, branch, %{
          "online" => "true",
          "skip_confirmation_call" => "true"
        })

      hold(ctx)
      drain()

      assert %{status: :accepted} = Repo.get!(Order, ctx.order.id)
      assert [%{status: :paid}] = Payments.list(ctx.order.id)
    end
  end

  describe "refunds" do
    setup %{conn: conn, branch: branch, cart_id: cart_id} do
      stub_yookassa(self())
      body = conn |> post(~p"/client/orders", params(branch, cart_id)) |> json_response(200)
      order = Repo.get!(Order, body["data"]["id"])
      [payment] = Payments.list(order.id)
      id = payment.external_id

      remote_api(self(), id, "waiting_for_capture")
      {:ok, _} = Delivest.Payments.Online.sync(id)

      staff = insert(:staff, role: insert(:role, permissions: ["admin"]))

      insert(:staff_branch,
        staff: staff,
        branch: Repo.get!(Delivest.Identity.Branch, order.branch_id)
      )

      {:ok, _} =
        Delivest.Oms.Orders.advance_order(Repo.get!(Order, order.id), :accepted, {:staff, staff})

      drain()
      assert [%{status: :paid}] = Payments.list(order.id)
      flush_remote()

      %{order: Repo.get!(Order, order.id), payment: hd(Payments.list(order.id)), id: id}
    end

    defp flush_remote do
      receive do
        {:remote, _, _, _, _} -> flush_remote()
      after
        0 -> :ok
      end
    end

    test "a refund is sent once with the refund id as the key and closed by the webhook", ctx do
      assert {:ok, refund} = Payments.refund(ctx.payment, 300, %{reason: "order changed"})
      remote_api(self(), ctx.id, "succeeded")
      drain()

      assert_received {:remote, "POST", path, headers, raw}
      assert String.ends_with?(path, "/refunds")
      assert {"idempotence-key", refund.id} in headers
      assert %{"payment_id" => id, "amount" => %{"value" => "3.00"}} = Jason.decode!(raw)
      assert id == ctx.id

      assert [%{refunds: [%{status: :pending, external_id: "refund-1"}]}] =
               Payments.list(ctx.order.id)

      assert {:ok, _} = Delivest.Payments.Online.sync_refund("refund-1")
      assert {:ok, _} = Delivest.Payments.Online.sync_refund("refund-1")
      assert [%{refunds: [%{status: :succeeded}]}] = Payments.list(ctx.order.id)
      assert Payments.balance(ctx.order) == :refunded
    end

    test "a refund cannot exceed what is left of the payment", ctx do
      assert {:ok, _} = Payments.refund(ctx.payment, 200)
      assert {:error, :refund_too_large} = Payments.refund(ctx.payment, 200)
      assert {:ok, _} = Payments.refund(ctx.payment, 100)
    end

    test "lowering the total of a paid order refunds the difference", ctx do
      remote_api(self(), ctx.id, "succeeded", "2.00")
      lowered = %{ctx.order | total_amount: 100}

      assert {:ok, _} = Payments.sync(Repo, lowered)
      drain()

      assert [%{refunds: [%{amount: 200}]}] = Payments.list(ctx.order.id)
      assert_received {:remote, "POST", path, _headers, raw}
      assert String.ends_with?(path, "/refunds")
      assert %{"amount" => %{"value" => "2.00"}} = Jason.decode!(raw)
    end

    test "a fully refunded payment takes no more refunds", ctx do
      [payment] = Payments.list(ctx.order.id)
      {:ok, _} = Payments.refund(payment, 300)
      drain()
      assert {:error, :refund_too_large} = Payments.refund(payment, 1)
    end
  end

  describe "resizing a hold" do
    test "lowering the total of an unpaid hold lowers the sum that is captured", %{
      conn: conn,
      branch: branch,
      cart_id: cart_id
    } do
      stub_yookassa(self())
      body = conn |> post(~p"/client/orders", params(branch, cart_id)) |> json_response(200)
      order = Repo.get!(Order, body["data"]["id"])
      [payment] = Payments.list(order.id)
      id = payment.external_id

      Req.Test.stub(Delivest.HTTP.Client, fn conn ->
        Req.Test.json(conn, %{
          "id" => id,
          "status" => "waiting_for_capture",
          "amount" => %{"value" => "3.00", "currency" => "RUB"}
        })
      end)

      {:ok, _} = Delivest.Payments.Online.sync(id)
      assert {:ok, _} = Payments.sync(Repo, %{Repo.get!(Order, order.id) | total_amount: 200})
      assert [%{amount: 200, status: :authorized}] = Payments.list(order.id)

      assert {:ok, _} = Payments.sync(Repo, %{Repo.get!(Order, order.id) | total_amount: 900})
      assert [%{amount: 300}] = Payments.list(order.id)
    end
  end
end
