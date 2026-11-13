defmodule Delivest.Integrations.RkeeperTest do
  use Delivest.DataCase, async: false
  use Oban.Testing, repo: Delivest.Repo

  import Ecto.Query
  import Delivest.Factory

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Crm.{BranchSettings, SyncWorker}
  alias Delivest.Integrations.{Crm, Rkeeper}
  alias Delivest.Integrations.Rkeeper.{Poller, PollWorker}
  alias Delivest.Integrations.Poller.Worker, as: BranchPollWorker
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
    do:
      perform_job(SyncWorker, %{
        "order_id" => order.id,
        "branch_id" => order.branch_id,
        "generation" => Crm.get_branch_settings(order.branch_id).generation
      })

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
    assert :more = Poller.poll(order.branch_id)
    assert_enqueued(worker: PollWorker, queue: :rkeeper_polling, args: %{order_id: order.id})
    assert :ok = perform_job(PollWorker, %{"order_id" => order.id})
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

    assert :more = Poller.poll(order.branch_id)
    assert :ok = perform_job(PollWorker, %{"order_id" => order.id})
    assert %Order{crm: %{status: "sent", external_id: "g-2"}} = Orders.get_order(order.id)
  end

  test "a task response for an old ref cannot confirm a retried order", %{order: order} do
    stub(%{
      "IsMainSystemAvailable" => %{"taskResponse" => %{"isAvailable" => true}},
      "CreateOrder" => %{"taskGuid" => "t-1"}
    })

    :ok = sync(order)

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      {:ok, _updated} =
        order.id
        |> Orders.get_order()
        |> Orders.update_order_crm(%{ref: "t-2"})

      Req.Test.json(conn, %{"taskResponse" => %{"order" => %{"orderGuid" => "g-old"}}})
    end)

    assert :ok = perform_job(PollWorker, %{"order_id" => order.id})

    assert %Order{crm: %{status: "confirming", ref: "t-2", external_id: nil}} =
             Orders.get_order(order.id)
  end

  test "removing CRM during a task response leaves the order unchanged", %{order: order} do
    stub(%{
      "IsMainSystemAvailable" => %{"taskResponse" => %{"isAvailable" => true}},
      "CreateOrder" => %{"taskGuid" => "t-1"}
    })

    :ok = sync(order)

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      order.id
      |> Orders.get_order()
      |> Ecto.Changeset.change(crm: nil)
      |> Repo.update!()

      Req.Test.json(conn, %{"taskResponse" => %{"order" => %{"orderGuid" => "g-old"}}})
    end)

    assert :ok = perform_job(PollWorker, %{"order_id" => order.id})
    assert %Order{crm: nil} = Orders.get_order(order.id)
  end

  test "branch polling fans out unique jobs and skips an inactive order", %{order: order} do
    stub(%{
      "IsMainSystemAvailable" => %{"taskResponse" => %{"isAvailable" => true}},
      "CreateOrder" => %{"taskResponse" => %{"order" => %{"orderGuid" => "g-1"}}}
    })

    :ok = sync(order)

    assert :ok =
             perform_job(BranchPollWorker, %{"poller" => "rkeeper", "target" => order.branch_id})

    assert :more = Poller.poll(order.branch_id)
    assert [%{args: %{"order_id" => id}}] = all_enqueued(worker: PollWorker)
    assert id == order.id
    assert :ok = PollWorker.perform(%Oban.Job{args: %{"order_id" => Ecto.UUID.generate()}})

    {:ok, _} =
      Orders.cancel_order(Orders.get_order(order.id), :system, %{"cancel_reason" => "other"})

    assert :ok = perform_job(PollWorker, %{"order_id" => order.id})
    refute_received {:rkeeper, %{"taskType" => "GetOrderState"}, _}
  end

  test "executing and retryable per-order jobs stay unique", %{order: order} do
    stub(%{
      "IsMainSystemAvailable" => %{"taskResponse" => %{"isAvailable" => true}},
      "CreateOrder" => %{"taskResponse" => %{"order" => %{"orderGuid" => "g-1"}}}
    })

    :ok = sync(order)
    assert :more = Poller.poll(order.branch_id)
    [job] = all_enqueued(worker: PollWorker)

    for state <- ["executing", "retryable"] do
      Repo.update!(Ecto.Changeset.change(job, state: state))
      assert :more = Poller.poll(order.branch_id)

      assert 1 ==
               Repo.aggregate(
                 from(j in Oban.Job, where: j.worker == ^job.worker),
                 :count
               )
    end
  end

  test "temporary polling failures retry without rejecting a confirming order", %{order: order} do
    stub(%{
      "IsMainSystemAvailable" => %{"taskResponse" => %{"isAvailable" => true}},
      "CreateOrder" => %{"taskGuid" => "t-1"}
    })

    :ok = sync(order)
    handler_id = "rkeeper-active-order-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:delivest, :rkeeper, :active_order],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:active_order_age, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    Req.Test.stub(Delivest.HTTP.Client, &Req.Test.transport_error(&1, :timeout))

    assert {:error, {:connection_error, _message, :timeout}} =
             perform_job(PollWorker, %{"order_id" => order.id})

    assert %Order{crm: %{status: "confirming", ref: "t-1"}} = Orders.get_order(order.id)

    assert_receive {:active_order_age, %{age_seconds: age}, %{order_id: id, branch_id: branch_id}}
    assert age >= 0
    assert id == order.id
    assert branch_id == order.branch_id
  end

  test "gateway and unexpected task responses do not reject order creation", %{order: order} do
    stub(%{
      "IsMainSystemAvailable" => %{"taskResponse" => %{"isAvailable" => true}},
      "CreateOrder" => %{"taskGuid" => "t-1"}
    })

    :ok = sync(order)

    for status <- [401, 429, 502] do
      Req.Test.stub(Delivest.HTTP.Client, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(status, Jason.encode!(%{"error" => %{"desc" => "gateway"}}))
      end)

      assert {:error, {:http_error, ^status, _body}} =
               perform_job(PollWorker, %{"order_id" => order.id})

      assert %Order{crm: %{status: "confirming"}} = Orders.get_order(order.id)
    end

    Req.Test.stub(Delivest.HTTP.Client, &Req.Test.json(&1, %{"unexpected" => true}))

    assert {:error, {:unexpected_response, %{"unexpected" => true}}} =
             perform_job(PollWorker, %{"order_id" => order.id})

    assert %Order{crm: %{status: "confirming"}} = Orders.get_order(order.id)
  end

  test "an explicit task failure rejects a confirming order", %{order: order} do
    stub(%{
      "IsMainSystemAvailable" => %{"taskResponse" => %{"isAvailable" => true}},
      "CreateOrder" => %{"taskGuid" => "t-1"},
      "GetTaskResponse" => %{"taskResponse" => %{"error" => %{"desc" => "Rejected"}}}
    })

    :ok = sync(order)
    assert :ok = perform_job(PollWorker, %{"order_id" => order.id})
    assert %Order{crm: %{status: "failed"}} = Orders.get_order(order.id)
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
