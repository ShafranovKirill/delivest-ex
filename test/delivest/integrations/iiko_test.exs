defmodule Delivest.Integrations.IikoTest do
  use DelivestWeb.ConnCase, async: true
  use Oban.Testing, repo: Delivest.Repo

  import Delivest.Factory

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Crm.{BranchSettings, CommandWorker, SyncWorker}
  alias Delivest.Integrations.{Crm, Iiko, Inbox}
  alias Delivest.Integrations.Iiko.OrderPayload
  alias Delivest.Net.ProductExternalId
  alias Delivest.{Oms, Repo}
  alias Delivest.Oms.{Carts, Order, Orders}

  @settings %Iiko.Settings{
    api_key: "key",
    organization_id: "org-1",
    terminal_group_id: "tg-1",
    webhook_token: "hook",
    cash_payment_type_id: "pt-cash",
    card_payment_type_id: "pt-card"
  }

  setup do
    branch = insert(:branch, is_active: true)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{enabled: true, provider: :iiko, iiko: @settings}
    })

    product = insert_branch_product(branch.id, price: 45_050)

    Repo.insert!(%ProductExternalId{
      entity_id: product.id,
      branch_id: branch.id,
      provider: "iiko",
      external_id: "iiko-pizza"
    })

    {:ok, cart} = Carts.create_cart(%{session_id: "iiko-#{branch.id}", branch_id: branch.id})
    {:ok, _, _} = Carts.add_item(cart.id, product.id, 2)

    {:ok, order} =
      Oms.create_order(%{
        "cart_id" => cart.id,
        "branch_id" => branch.id,
        "fulfillment_type" => "pickup",
        "payment_method" => "cash",
        "customer_phone" => "+79001112233",
        "customer_name" => "Анна",
        "comment" => "Без лука"
      })

    %{order: order, branch: branch}
  end

  defp stub(fun) do
    test = self()

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:iiko, conn.request_path, Jason.decode!(body)})

      case conn.request_path do
        "/api/1/access_token" -> Req.Test.json(conn, %{"token" => "jwt"})
        path -> fun.(conn, path)
      end
    end)
  end

  test "the order body carries items, payment and the customer", %{order: order} do
    order = Repo.preload(order, [items: :modifiers], force: true)
    articles = %{products: %{hd(order.items).product_id => "iiko-pizza"}, modifiers: %{}}

    assert {:ok, body} = OrderPayload.build(order, @settings, articles)
    assert body.id == order.id
    assert body.externalNumber == order.number
    assert body.orderServiceType == "DeliveryByClient"
    assert body.customer == %{name: "Анна", type: "one-time"}
    assert [%{productId: "iiko-pizza", amount: 2, price: 450.5, type: "Product"}] = body.items

    assert [
             %{
               paymentTypeKind: "Cash",
               paymentTypeId: "pt-cash",
               sum: 901.0,
               isProcessedExternally: false
             }
           ] = body.payments

    assert {:error, {:missing_payment_type, :online}} =
             OrderPayload.build(%{order | payment_method: :online}, @settings, articles)
  end

  test "creation waits for the webhook, then statuses follow iiko", %{conn: conn, order: order} do
    stub(fn conn, path ->
      case path do
        "/api/1/deliveries/create" ->
          Req.Test.json(conn, %{"correlationId" => "corr-1"})

        "/api/1/deliveries/by_id" ->
          Req.Test.json(conn, %{
            "orders" => [
              %{
                "id" => order.id,
                "creationStatus" => "Success",
                "order" => %{"number" => 77, "status" => "CookingStarted"}
              }
            ]
          })

        "/api/1/deliveries/change_comment" ->
          Req.Test.json(conn, %{"correlationId" => "corr-2"})
      end
    end)

    :ok = perform_job(SyncWorker, %{"order_id" => order.id, "branch_id" => order.branch_id})
    assert_received {:iiko, "/api/1/deliveries/create", %{"order" => %{"id" => id}}}
    assert id == order.id
    assert %Order{crm: %{status: "confirming", ref: "corr-1"}} = Orders.get_order(order.id)

    conn
    |> post("/integrations/crm/iiko/wrong", %{"_json" => []})
    |> json_response(404)

    conn
    |> put_req_header("content-type", "application/json")
    |> post(
      "/integrations/crm/iiko/hook",
      Jason.encode!([
        %{
          "eventType" => "DeliveryOrderUpdate",
          "eventTime" => "2026-10-30 12:00:00.000",
          "correlationId" => "corr-1",
          "eventInfo" => %{"id" => order.id}
        }
      ])
    )
    |> json_response(200)

    [message] = Inbox.list(:iiko)
    assert {:ok, _order} = Iiko.Webhook.handle_inbox(message)

    order = Orders.get_order(order.id)
    assert %Order{status: :preparing, crm: %{status: "sent", external_number: "77"}} = order
    assert Crm.can?(order, :cancel)
  end

  test "a creation error fails the sync", %{order: order} do
    stub(fn conn, path ->
      case path do
        "/api/1/deliveries/create" ->
          Req.Test.json(conn, %{"correlationId" => "corr-1"})

        "/api/1/deliveries/by_id" ->
          Req.Test.json(conn, %{
            "orders" => [
              %{
                "id" => order.id,
                "creationStatus" => "Error",
                "errorInfo" => %{"message" => "Product not found"}
              }
            ]
          })
      end
    end)

    :ok = perform_job(SyncWorker, %{"order_id" => order.id, "branch_id" => order.branch_id})
    order = Orders.get_order(order.id)
    Iiko.Webhook.refresh(order, @settings)

    assert %Order{crm: %{status: "failed", last_error: "Product not found"}} =
             Orders.get_order(order.id)
  end

  test "comment changes go to iiko as a command", %{order: order} do
    stub(fn conn, _path -> Req.Test.json(conn, %{"correlationId" => "c"}) end)

    order = %{
      order
      | crm: %{order.crm | status: "sent", external_id: order.id},
        comment: "Позвонить"
    }

    assert :ok =
             Iiko.update_order(order, %{"comment" => %{"from" => "a", "to" => "b"}}, @settings)

    assert_received {:iiko, "/api/1/deliveries/change_comment", %{"comment" => "Позвонить"}}
    assert :ok = Iiko.cancel_order(order, nil, @settings)
    assert_received {:iiko, "/api/1/deliveries/cancel", %{"orderId" => _id}}
    refute_enqueued(worker: CommandWorker)
  end

  test "stops come from the terminal group" do
    stub(fn conn, "/api/1/stop_lists" ->
      Req.Test.json(conn, %{
        "terminalGroupStopLists" => [
          %{
            "items" => [
              %{
                "terminalGroupId" => "tg-1",
                "items" => [
                  %{"productId" => "a", "balance" => 0},
                  %{"productId" => "b", "balance" => 3}
                ]
              },
              %{"terminalGroupId" => "tg-2", "items" => [%{"productId" => "c", "balance" => 0}]}
            ]
          }
        ]
      })
    end)

    assert {:ok, ["a"]} = Iiko.fetch_stops(@settings)
  end
end
