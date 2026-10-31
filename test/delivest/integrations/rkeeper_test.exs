defmodule Delivest.Integrations.RkeeperTest do
  use Delivest.DataCase, async: false
  use Oban.Testing, repo: Delivest.Repo

  import Delivest.Factory

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Crm.{BranchSettings, SyncWorker}
  alias Delivest.Integrations.{Crm, Rkeeper}
  alias Delivest.Net.ProductExternalId
  alias Delivest.Oms
  alias Delivest.Oms.{Carts, Order, Orders}

  @settings %Rkeeper.Settings{
    object_id: "199990377",
    sandbox: true,
    pickup_category_code: "1",
    pickup_type_code: "4"
  }

  setup do
    config = Application.get_env(:delivest, Rkeeper, [])
    Application.put_env(:delivest, Rkeeper, token: "agg-token")
    on_exit(fn -> Application.put_env(:delivest, Rkeeper, config) end)

    branch = insert(:branch, is_active: true)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{enabled: true, provider: :rkeeper, rkeeper: @settings}
    })

    product = insert_branch_product(branch.id, price: 30_000, name: "Борщ")

    Repo.insert!(%ProductExternalId{
      entity_id: product.id,
      branch_id: branch.id,
      provider: "rkeeper",
      external_id: "1024545"
    })

    {:ok, cart} = Carts.create_cart(%{session_id: "rk-#{branch.id}", branch_id: branch.id})
    {:ok, _, _} = Carts.add_item(cart.id, product.id, 1)

    {:ok, order} =
      Oms.create_order(%{
        "cart_id" => cart.id,
        "branch_id" => branch.id,
        "fulfillment_type" => "pickup",
        "payment_method" => "cash",
        "customer_phone" => "+79001112233",
        "customer_name" => "Иван"
      })

    %{order: order, branch: branch}
  end

  defp stub(responses) do
    test = self()

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      body = Jason.decode!(body)
      send(test, {:rkeeper, body, Plug.Conn.get_req_header(conn, "aggregatorauthentication")})
      Req.Test.json(conn, Map.fetch!(responses, body["taskType"]))
    end)
  end

  defp sync(order),
    do: perform_job(SyncWorker, %{"order_id" => order.id, "branch_id" => order.branch_id})

  test "the order reaches the pos and statuses come by polling", %{order: order} do
    stub(%{
      "IsMainSystemAvailable" => %{"taskResponse" => %{"isAvailable" => true}},
      "CreateOrder" => %{"taskResponse" => %{"order" => %{"orderGuid" => "g-1"}}},
      "GetOrderState" => %{"taskResponse" => %{"order" => %{"status" => "Cooking"}}}
    })

    :ok = sync(order)

    assert_received {:rkeeper, %{"taskType" => "CreateOrder", "params" => params}, ["agg-token"]}
    assert params["sync"]["objectId"] == "199990377"

    assert %{
             "originalOrderId" => number,
             "expeditionType" => "pickup",
             "payment" => %{"type" => "cash"},
             "products" => [%{"id" => "1024545", "price" => 300.0, "quantity" => 1}],
             "price" => %{"total" => 300.0},
             "orderCategoryCode" => 1,
             "orderTypeCode" => 4
           } = params["order"]

    assert number == order.number

    assert %Order{status: :accepted, crm: %{status: "sent", external_id: "g-1"}} =
             Orders.get_order(order.id)

    assert [_branch] = Rkeeper.active_branches()
    assert :more = Rkeeper.poll(order.branch_id)
    assert %Order{status: :preparing} = Orders.get_order(order.id)
  end

  test "a slow pos answers with a task that is polled", %{order: order} do
    stub(%{
      "IsMainSystemAvailable" => %{"taskResponse" => %{"isAvailable" => true}},
      "CreateOrder" => %{"taskGuid" => "t-1"},
      "GetTaskResponse" => %{"taskResponse" => %{"order" => %{"orderGuid" => "g-2"}}}
    })

    :ok = sync(order)
    assert %Order{crm: %{status: "confirming", ref: "t-1"}} = Orders.get_order(order.id)

    Rkeeper.poll(order.branch_id)
    assert %Order{crm: %{status: "sent", external_id: "g-2"}} = Orders.get_order(order.id)
  end

  test "an offline pos snoozes the sending", %{order: order} do
    stub(%{"IsMainSystemAvailable" => %{"taskResponse" => %{"isAvailable" => false}}})

    assert {:snooze, 120} = sync(order)
    assert {:error, :pos_offline} = Rkeeper.health_check(@settings)
    assert Crm.can?(%{order | crm: %{order.crm | provider: "rkeeper"}}, :cancel)
  end

  test "cancel and comment go as tasks", %{order: order} do
    stub(%{
      "CancelOrder" => %{"taskResponse" => %{}},
      "PatchOrder" => %{"taskResponse" => %{}}
    })

    order = %{order | crm: %{order.crm | external_id: "g-1"}, comment: "Позвонить"}
    assert :ok = Rkeeper.cancel_order(order, nil, @settings)
    assert_received {:rkeeper, %{"params" => %{"orderGuid" => "g-1", "voidReasonCode" => 1}}, _}

    assert :ok = Rkeeper.update_order(order, %{"comment" => %{}}, @settings)

    assert_received {:rkeeper,
                     %{
                       "params" => %{"fields" => [%{"name" => "Comment", "value" => "Позвонить"}]}
                     }, _}
  end

  test "a gateway error is permanent", %{order: order} do
    stub(%{
      "IsMainSystemAvailable" => %{"taskResponse" => %{}},
      "CreateOrder" => %{"error" => %{"wsError" => %{"desc" => "Dish not found"}}}
    })

    assert {:cancel, _reason} = sync(order)
    assert %Order{crm: %{status: "failed", last_error: error}} = Orders.get_order(order.id)
    assert error =~ "Dish not found"
  end
end
