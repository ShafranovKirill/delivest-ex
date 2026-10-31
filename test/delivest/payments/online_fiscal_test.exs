defmodule Delivest.Payments.OnlineFiscalTest do
  use DelivestWeb.ConnCase, async: true

  import Delivest.Factory

  alias Delivest.Fiscal
  alias Delivest.Fiscal.BranchSettings
  alias Delivest.Identity.Branch
  alias Delivest.Identity.Branch.{BranchInfo, PaymentSettings}
  alias Delivest.Integrations.{AtolOnline, Health, Yookassa}
  alias Delivest.Oms.{Order, Orders}
  alias Delivest.Payments
  alias Delivest.Payments.Online
  alias Delivest.Repo

  setup %{conn: conn} do
    branch = insert(:branch, is_active: true)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      payments: %PaymentSettings{online: true},
      fiscal: %BranchSettings{
        mode: :own,
        inn: "5544332219",
        sno: :usn_income,
        payment_address: "https://v5.online.atol.ru",
        email: "chek@pizza.ru",
        atol: %AtolOnline.Settings{
          login: "login-#{branch.id}",
          password: "secret",
          group_code: "group",
          sandbox: true,
          callback_token: "cb-token"
        }
      }
    })

    Repo.insert!(%Yookassa.Settings{shop_id: "1", secret_key: "k", webhook_token: "t"})

    Repo.insert!(%Health.Status{
      provider: "yookassa",
      status: :ok,
      checked_at: DateTime.utc_now()
    })

    product = insert_branch_product(branch.id, price: 300)
    conn = put_req_header(conn, "x-forwarded-for", "ip-#{System.unique_integer([:positive])}")
    conn = post(conn, ~p"/client/branches/#{branch.id}/select")
    conn = recycle_ip(conn)
    conn = get(conn, ~p"/client/cart?branch_id=#{branch.id}")
    cart_id = json_response(conn, 200)["data"]["id"]
    conn = post(recycle_ip(conn), ~p"/client/cart/#{cart_id}/items/#{product.id}")
    assert json_response(conn, 200)

    pid = self()

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(pid, {:call, conn.method, conn.request_path, raw})
      reply(conn)
    end)

    params = %{
      "cart_id" => cart_id,
      "branch_id" => branch.id,
      "fulfillment_type" => "pickup",
      "payment_method" => "online",
      "customer_phone" => "+79990001122",
      "customer_name" => "Иван"
    }

    body = conn |> recycle_ip() |> post(~p"/client/orders", params) |> json_response(200)
    order = Repo.get!(Order, body["data"]["id"])
    [payment] = Payments.list(order.id)
    {:ok, _} = Online.sync(payment.external_id)

    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    insert(:staff_branch, staff: staff, branch: Repo.get!(Branch, branch.id))

    %{order: order, payment: payment, staff: staff}
  end

  defp recycle_ip(conn) do
    ip = get_req_header(conn, "x-forwarded-for")
    conn |> recycle() |> put_req_header("x-forwarded-for", Enum.join(ip, ","))
  end

  defp reply(conn) do
    path = conn.request_path

    cond do
      String.ends_with?(path, "getToken") ->
        Req.Test.json(conn, %{"token" => "tok"})

      String.contains?(path, "/sell") ->
        Req.Test.json(conn, %{
          "uuid" => "u-#{System.unique_integer([:positive])}",
          "status" => "done"
        })

      String.ends_with?(path, "/v3/payments") ->
        Req.Test.json(conn, %{
          "id" => "pay-1",
          "status" => "pending",
          "confirmation" => %{"confirmation_url" => "https://pay.example/1"}
        })

      String.ends_with?(path, "/refunds") ->
        Req.Test.json(conn, %{"id" => "refund-1", "status" => "pending", "amount" => rub("3.00")})

      String.contains?(path, "/refunds/") ->
        Req.Test.json(conn, %{
          "id" => "refund-1",
          "status" => "succeeded",
          "amount" => rub("3.00")
        })

      true ->
        status =
          if String.ends_with?(path, "/capture"), do: "succeeded", else: "waiting_for_capture"

        id = path |> String.split("/") |> Enum.find(&String.contains?(&1, "-")) || "pay"
        Req.Test.json(conn, %{"id" => id, "status" => status, "amount" => rub("3.00")})
    end
  end

  defp rub(value), do: %{"value" => value, "currency" => "RUB"}

  defp drain do
    for _round <- 1..3,
        queue <- [:default, :events, :fiscal],
        do: Oban.drain_queue(queue: queue, with_safety: false, with_recursion: true)
  end

  defp sell_bodies do
    receive do
      {:call, "POST", path, raw} ->
        if String.contains?(path, "/sell"),
          do: [Jason.decode!(raw) | sell_bodies()],
          else: sell_bodies()

      {:call, _method, _path, _raw} ->
        sell_bodies()
    after
      0 -> []
    end
  end

  defp accept(ctx),
    do: Orders.advance_order(Repo.get!(Order, ctx.order.id), :accepted, {:staff, ctx.staff})

  test "the capture prints the prepayment receipt", ctx do
    {:ok, _} = accept(ctx)
    drain()

    assert [%{kind: :sell, stage: :full_prepayment, status: :done, amount: 300}] =
             Fiscal.list(ctx.order.id)

    assert [%{fiscalized_by: :us}] = Payments.list(ctx.order.id)

    assert [%{"receipt" => receipt}] = sell_bodies()
    assert [%{"payment_method" => "full_prepayment"}] = receipt["items"]
    assert [%{"type" => 1, "sum" => 3}] = receipt["payments"]
  end

  test "completing the order prints the final receipt that offsets the prepayment", ctx do
    {:ok, _} = accept(ctx)
    drain()
    _ = sell_bodies()

    {:ok, _} = Orders.advance_order(Repo.get!(Order, ctx.order.id), :completed, :system)
    drain()

    assert [%{stage: :full_prepayment}, %{kind: :sell, stage: :full_payment, amount: 300}] =
             Fiscal.list(ctx.order.id)

    assert [%{"receipt" => receipt}] = sell_bodies()
    assert [%{"payment_method" => "full_payment"}] = receipt["items"]
    assert [%{"type" => 2, "sum" => 3}] = receipt["payments"]
  end

  test "a refund prints a refund receipt", ctx do
    {:ok, _} = accept(ctx)
    drain()
    _ = sell_bodies()

    [payment] = Payments.list(ctx.order.id)
    {:ok, _} = Payments.refund(payment, 300)
    drain()
    assert {:ok, _} = Online.sync_refund("refund-1")
    drain()

    assert [_prepayment, %{kind: :sell_refund, stage: :full_prepayment, amount: 300}] =
             Fiscal.list(ctx.order.id)
  end

  test "cancelling a captured order refunds it", ctx do
    {:ok, _} = accept(ctx)
    drain()

    {:ok, _} =
      Orders.cancel_order(Repo.get!(Order, ctx.order.id), {:staff, ctx.staff}, %{
        "cancel_reason" => "other"
      })

    drain()

    assert [%{refunds: [%{amount: 300}]}] = Payments.list(ctx.order.id)
  end
end
