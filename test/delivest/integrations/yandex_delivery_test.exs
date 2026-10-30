defmodule Delivest.Integrations.YandexDeliveryTest do
  use Delivest.DataCase, async: true
  use Oban.Testing, repo: Delivest.Repo

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Couriers
  alias Delivest.Couriers.Delivery
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.YandexDelivery
  alias Delivest.Integrations.Poller.Worker, as: PollWorker
  alias Delivest.Integrations.YandexDelivery.{ClaimLookupWorker, Journal, Settings}
  alias Delivest.Oms.{Order, Orders, OrderTransition}

  @settings %Settings{token: "y-token", contact_email: "kitchen@example.com"}

  setup do
    {:ok, yandex} = Agent.start_link(fn -> %{claims: %{}, created: 0} end)
    test_pid = self()

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      conn = Plug.Conn.fetch_query_params(conn)
      body = if body == "", do: %{}, else: Jason.decode!(body)
      path = String.replace_prefix(conn.request_path, "/b2b/cargo/integration/v2", "")
      send(test_pid, {:yandex, path, conn.query_params, body})
      respond(conn, yandex, path, conn.query_params, body)
    end)

    %{yandex: yandex}
  end

  defp respond(conn, yandex, "/claims/create", %{"request_id" => request_id}, _body) do
    claim_id = "claim-" <> request_id

    case Agent.get_and_update(yandex, fn state ->
           {state[:failures], Map.put(state, :failures, tl_or_empty(state[:failures]))}
         end) do
      [:timeout | _] -> Req.Test.transport_error(conn, :timeout)
      [:lost | _] -> create_claim(yandex, claim_id, :lost, conn)
      [:error | _] -> Plug.Conn.send_resp(conn, 500, "")
      _none -> create_claim(yandex, claim_id, :ok, conn)
    end
  end

  defp respond(conn, yandex, "/claims/search", _query, %{"external_order_id" => number}) do
    claims =
      yandex
      |> Agent.get(& &1.claims)
      |> Map.values()
      |> Enum.filter(&Map.has_key?(&1, "id"))

    Req.Test.json(conn, %{"claims" => if(number, do: claims, else: [])})
  end

  defp respond(conn, yandex, "/claims/info", %{"claim_id" => claim_id}, _body),
    do: Req.Test.json(conn, Agent.get(yandex, &get_in(&1, [:claims, claim_id])))

  defp respond(conn, yandex, "/claims/journal", _query, _body) do
    events =
      yandex
      |> Agent.get(& &1.claims)
      |> Enum.map(fn {id, claim} -> %{"claim_id" => id, "new_status" => claim["status"]} end)

    Req.Test.json(conn, %{"cursor" => "cursor-#{length(events)}", "events" => events})
  end

  defp respond(conn, _yandex, "/claims/set-point-ready", _query, _body),
    do: Req.Test.json(conn, %{"id" => "ok"})

  defp respond(conn, _yandex, "/claims/cancel-info", _query, _body),
    do: Req.Test.json(conn, %{"cancel_state" => "free"})

  defp respond(conn, yandex, "/claims/cancel", %{"claim_id" => claim_id}, _body) do
    set_status(yandex, claim_id, "cancelled")
    Req.Test.json(conn, %{"id" => claim_id, "status" => "cancelled"})
  end

  defp respond(conn, yandex, "/claims/accept", %{"claim_id" => claim_id}, _body) do
    set_status(yandex, claim_id, "accepted")
    Req.Test.json(conn, %{"id" => claim_id, "status" => "accepted"})
  end

  defp respond(%{method: "GET"} = conn, _yandex, "/claims/tracking-links", _query, _body) do
    Req.Test.json(conn, %{
      "route_points" => [
        %{"id" => 11, "type" => "source", "visit_order" => 1, "sharing_link" => "https://a"},
        %{"id" => 12, "type" => "destination", "visit_order" => 2, "sharing_link" => "https://b"}
      ]
    })
  end

  defp respond(conn, _yandex, "/driver-voiceforwarding", _query, _body),
    do: Req.Test.json(conn, %{"phone" => "+79000000001", "ext" => "0163"})

  defp tl_or_empty([_ | rest]), do: rest
  defp tl_or_empty(_none), do: []

  defp create_claim(yandex, claim_id, mode, conn) do
    Agent.update(yandex, fn state ->
      state
      |> put_in([:claims, claim_id], claim(claim_id, "new"))
      |> Map.update!(:created, &(&1 + 1))
    end)

    if mode == :lost,
      do: Req.Test.transport_error(conn, :timeout),
      else: Req.Test.json(conn, %{"id" => claim_id, "status" => "new", "version" => 1})
  end

  defp claim(claim_id, status) do
    %{
      "id" => claim_id,
      "status" => status,
      "version" => 3,
      "pricing" => %{"offer" => %{"price" => "250.00"}},
      "route_points" => [
        %{"id" => 11, "type" => "source"},
        %{"id" => 12, "type" => "destination"}
      ]
    }
  end

  defp set_status(yandex, claim_id, status, extra \\ %{}) do
    Agent.update(yandex, fn state ->
      update_in(
        state,
        [:claims, claim_id],
        &(&1 |> Map.put("status", status) |> Map.merge(extra))
      )
    end)
  end

  defp branch(settings \\ @settings) do
    branch = insert(:branch, name: "Центральный")

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      city: "Тюмень",
      address: "ул Ленина, 1",
      latitude: 57.15,
      longitude: 65.53,
      phone_number: "+73452000000",
      couriers: %{source: :yandex, search: :preparing},
      yandex_delivery: settings
    })

    branch
  end

  defp operator(branch) do
    insert(:staff, role: build(:role, permissions: ["orders.update"]), branches: [branch])
    |> Repo.preload([:role, :branches])
  end

  defp order(branch, changes \\ []) do
    client = insert(:client, phone: "+79001112233", name: "Анна")

    branch.id
    |> order_fixture(price: 30_000, quantity: 2)
    |> Ecto.Changeset.change(
      Keyword.merge(
        [
          fulfillment_type: :delivery,
          client_id: client.id,
          customer_phone: client.phone,
          customer_name: client.name,
          total_amount: 60_000,
          address: %Order.Address{
            city: "Тюмень",
            street: "ул Республики",
            house: "10",
            entrance: "2",
            floor: "5",
            apartment: "48",
            intercom: "48К",
            latitude: 57.1,
            longitude: 65.5
          }
        ],
        changes
      )
    )
    |> Repo.update!()
  end

  defp cooking(order, operator) do
    Enum.reduce([:accepted, :preparing], order, fn to, order ->
      {:ok, order} = Orders.advance_order(order, to, {:staff, operator})
      deliver_events()
      order
    end)
  end

  defp poll(branch) do
    result = perform_job(PollWorker, %{poller: "yandex_delivery", target: branch.id})
    deliver_events()
    result
  end

  describe "a lost answer to claim creation" do
    setup do
      Application.put_env(:delivest, :yandex_delivery_retry_pause, 0)
      on_exit(fn -> Application.delete_env(:delivest, :yandex_delivery_retry_pause) end)
    end

    defp fail_creation(yandex, failures),
      do: Agent.update(yandex, &Map.put(&1, :failures, failures))

    test "a timeout is retried with the same request id", %{yandex: yandex} do
      fail_creation(yandex, [:timeout])
      branch = branch()
      order = order(branch) |> cooking(operator(branch))

      delivery = Couriers.active(order.id)
      assert delivery.external_id == "claim-" <> delivery.id
      assert Agent.get(yandex, & &1.created) == 1
      assert_received {:yandex, "/claims/create", %{"request_id" => id}, _body}
      assert_received {:yandex, "/claims/create", %{"request_id" => ^id}, _body}
    end

    test "when retries get no answer the claim is looked up by the order number", %{
      yandex: yandex
    } do
      fail_creation(yandex, [:lost, :timeout, :timeout])
      branch = branch()
      order = order(branch) |> cooking(operator(branch))

      delivery = Couriers.active(order.id)
      assert delivery.status == :searching
      assert delivery.external_id == nil

      assert :ok = perform_job(ClaimLookupWorker, lookup_args(delivery, order))
      assert Repo.reload!(delivery).external_id == "claim-" <> delivery.id
      assert Agent.get(yandex, & &1.created) == 1
    end

    test "no claim within the window closes the attempt", %{yandex: yandex} do
      fail_creation(yandex, [:timeout, :timeout, :timeout])
      branch = branch()
      order = order(branch) |> cooking(operator(branch))
      delivery = Couriers.active(order.id)

      args = %{lookup_args(delivery, order) | "started_at" => System.os_time(:second) - 301}
      assert :ok = perform_job(ClaimLookupWorker, args)
      assert %Delivery{status: :failed, close_reason: :provider_error} = Repo.reload!(delivery)
    end

    test "no claim yet schedules another lookup", %{yandex: yandex} do
      fail_creation(yandex, [:timeout, :timeout, :timeout])
      branch = branch()
      order = order(branch) |> cooking(operator(branch))
      delivery = Couriers.active(order.id)

      assert :ok = perform_job(ClaimLookupWorker, lookup_args(delivery, order))
      assert Repo.reload!(delivery).status == :searching
      assert_enqueued(worker: ClaimLookupWorker, args: %{delivery_id: delivery.id})
    end

    defp lookup_args(delivery, order),
      do: %{
        "delivery_id" => delivery.id,
        "number" => order.number,
        "started_at" => System.os_time(:second)
      }
  end

  describe "preorders" do
    test "a cook time inside the window becomes the due time" do
      branch = branch()
      soon = DateTime.utc_now() |> DateTime.add(90, :minute) |> DateTime.truncate(:second)

      order(branch, cook_by: soon) |> cooking(operator(branch))
      assert_received {:yandex, "/claims/create", _query, %{"due" => due}}
      assert {:ok, ^soon, _} = DateTime.from_iso8601(due)
    end

    test "a cook time outside the window is not sent" do
      branch = branch()
      far = DateTime.utc_now() |> DateTime.add(600, :minute) |> DateTime.truncate(:second)

      order(branch, cook_by: far) |> cooking(operator(branch))
      assert_received {:yandex, "/claims/create", _query, body}
      refute Map.has_key?(body, "due")
    end
  end

  describe "order readiness" do
    test "the claim asks to be notified and gets the readiness when the kitchen is done" do
      branch = branch()
      staff = operator(branch)
      order = order(branch) |> cooking(staff)
      delivery = Couriers.active(order.id)
      assert_received {:yandex, "/claims/create", _query, body}
      assert [%{"should_notify_on_order_readiness" => true}, _destination] = body["route_points"]
      refute_received {:yandex, "/claims/set-point-ready", _query, _body}

      {:ok, _order} = Orders.advance_order(order, :ready, {:staff, staff})
      deliver_events()

      claim_id = delivery.external_id
      assert_received {:yandex, "/claims/set-point-ready", %{"claim_id" => ^claim_id}, body}
      assert body == %{"visit_order" => 1}
    end

    test "nothing is called without an active claim" do
      branch = branch()
      staff = operator(branch)
      order = order(branch)
      {:ok, order} = Orders.advance_order(order, :accepted, {:staff, staff})
      {:ok, _order} = Orders.advance_order(order, :preparing, {:staff, staff})
      deliver_events()
      Couriers.active(order.id) |> then(&Couriers.give_up/1)

      order = Repo.reload!(order)
      {:ok, _order} = Orders.advance_order(order, :ready, {:staff, staff})
      deliver_events()
      refute_received {:yandex, "/claims/set-point-ready", _query, _body}
    end
  end

  describe "calling a courier" do
    test "creates a claim when cooking begins and switches cash to card" do
      branch = branch()
      order = order(branch) |> cooking(operator(branch))

      assert %Delivery{provider: :yandex, status: :searching} =
               delivery = Couriers.active(order.id)

      assert delivery.external_id == "claim-" <> delivery.id
      assert delivery.details["status"] == "new"

      assert_received {:yandex, "/claims/create", %{"request_id" => request_id}, body}
      assert request_id == delivery.id

      assert [source, destination] = body["route_points"]
      assert source["address"]["coordinates"] == [65.53, 57.15]

      assert source["contact"] == %{
               "name" => "Центральный",
               "phone" => "+73452000000",
               "email" => "kitchen@example.com"
             }

      assert destination["address"]["fullname"] == "Тюмень, ул Республики, 10"
      assert destination["address"]["sflat"] == "48"
      assert destination["contact"] == %{"name" => "Анна", "phone" => "+79001112233"}
      assert destination["external_order_id"] == order.number
      assert destination["payment_on_delivery"] == %{"payment_method" => "card"}
      assert body["client_requirements"] == %{"taxi_class" => "courier"}
      refute Map.has_key?(body, "auto_accept")

      assert [%{"cost_value" => "300.00", "quantity" => 2, "fiscalization" => fiscal}] =
               body["items"]

      assert fiscal == %{"vat_code_str" => "vat_none", "item_type" => "product"}

      assert Repo.reload!(order).payment_method == :card_offline
      assert_enqueued(worker: PollWorker, args: %{poller: "yandex_delivery", target: branch.id})
    end

    test "auto accept goes into the claim when it is enabled" do
      branch = branch(%{@settings | auto_accept: true})
      order(branch) |> cooking(operator(branch))

      assert_received {:yandex, "/claims/create", _query, %{"auto_accept" => true}}
    end

    test "online orders are not paid to the courier" do
      branch = branch()
      order(branch, payment_method: :online) |> cooking(operator(branch))

      assert_received {:yandex, "/claims/create", _query, body}
      refute Map.has_key?(Enum.at(body["route_points"], 1), "payment_on_delivery")
      refute Map.has_key?(hd(body["items"]), "fiscalization")
    end

    test "fits the item prices to the total after a discount" do
      branch = branch()
      order(branch, total_amount: 50_050, delivery_amount: 10_000) |> cooking(operator(branch))

      assert_received {:yandex, "/claims/create", _query, body}

      assert [goods, delivery] = body["items"]
      assert goods["cost_value"] == "400.50" and goods["quantity"] == 1
      assert delivery["cost_value"] == "100.00"
      assert delivery["fiscalization"]["item_type"] == "service"
    end

    test "a branch without settings gets no claim" do
      branch = branch(%Settings{})
      operator = operator(branch)
      order = order(branch) |> cooking(operator)

      refute_received {:yandex, "/claims/create", _query, _body}
      assert Couriers.active(order.id) == nil
      assert {:error, :not_configured} = Couriers.find(operator, Repo.reload!(order))
    end
  end

  describe "following the claim" do
    setup %{yandex: yandex} do
      branch = branch()
      operator = operator(branch)
      order = order(branch) |> cooking(operator)
      delivery = Couriers.active(order.id)
      %{branch: branch, operator: operator, order: order, delivery: delivery, yandex: yandex}
    end

    test "accepts the estimated claim and keeps the cursor", ctx do
      set_status(ctx.yandex, ctx.delivery.external_id, "ready_for_approval")

      assert :ok = poll(ctx.branch)

      assert_received {:yandex, "/claims/accept", %{"claim_id" => claim_id}, %{"version" => 3}}
      assert claim_id == ctx.delivery.external_id
      assert %Delivery{status: :searching} = Couriers.active(ctx.order.id)
      assert %Journal{cursor: "cursor-1"} = Repo.get(Journal, ctx.branch.id)
      assert_received {:yandex, "/claims/journal", _query, %{}}

      assert :ok = poll(ctx.branch)
      assert_received {:yandex, "/claims/journal", _query, %{"cursor" => "cursor-1"}}
    end

    test "the poller keeps polling while claims are active and is started by cron", ctx do
      assert :ok = poll(ctx.branch)

      assert_enqueued(
        worker: PollWorker,
        args: %{poller: "yandex_delivery", target: ctx.branch.id}
      )

      Repo.delete_all(Oban.Job)
      assert :ok = perform_job(PollWorker, %{poller: "yandex_delivery"})

      assert_enqueued(
        worker: PollWorker,
        args: %{poller: "yandex_delivery", target: ctx.branch.id}
      )

      assert {:error, :unknown_poller} = perform_job(PollWorker, %{poller: "nope", target: "x"})
    end

    test "claim requests go to the journal with the branch and the order", ctx do
      poll(ctx.branch)

      requests = Delivest.Integrations.Journal.list(:yandex_delivery, ctx.branch.id)
      assert Enum.any?(requests, &(&1.url =~ "/claims/create" and &1.order_id == ctx.order.id))
      assert Enum.any?(requests, &(&1.url =~ "/claims/journal" and &1.status == 200))
    end

    test "shows the courier, then moves the order on pickup and handover", ctx do
      set_status(ctx.yandex, ctx.delivery.external_id, "performer_found", %{
        "performer_info" => %{
          "courier_name" => "Иван",
          "car_model" => "Kia Rio",
          "car_number" => "А001АА72"
        }
      })

      poll(ctx.branch)

      assert %Delivery{status: :assigned, details: details} = Couriers.active(ctx.order.id)
      assert details["performer"] == %{"name" => "Иван", "car" => "Kia Rio, А001АА72"}
      assert details["phone"] == "+79000000001,,0163"
      assert details["tracking_url"] == "https://b"
      assert details["price"] == "250.00"
      assert_received {:yandex, "/driver-voiceforwarding", _query, %{"point_id" => 11}}

      {:ok, _order} =
        Orders.advance_order(Repo.reload!(ctx.order), :ready, {:staff, ctx.operator})

      set_status(ctx.yandex, ctx.delivery.external_id, "pickuped")
      poll(ctx.branch)

      assert %Order{status: :delivering} = Repo.reload!(ctx.order)
      assert %Delivery{status: :picked_up} = Couriers.active(ctx.order.id)

      set_status(ctx.yandex, ctx.delivery.external_id, "delivered_finish")
      assert :ok = poll(ctx.branch)

      assert %Order{status: :completed} = Repo.reload!(ctx.order)
      assert %Delivery{status: :delivered} = Repo.reload!(ctx.delivery)

      sources =
        OrderTransition
        |> where([t], t.order_id == ^ctx.order.id and t.source == :delivery)
        |> select([t], t.to)
        |> Repo.all()

      assert sources == [:delivering, :completed]
      assert YandexDelivery.poll(ctx.branch.id) == :done
    end

    test "a pickup before the kitchen marks it ready still moves the order", ctx do
      set_status(ctx.yandex, ctx.delivery.external_id, "pickuped")
      poll(ctx.branch)

      assert %Order{status: :delivering} = Repo.reload!(ctx.order)
      assert %Delivery{status: :picked_up} = Couriers.active(ctx.order.id)
    end

    test "calls a new courier when none was found", ctx do
      set_status(ctx.yandex, ctx.delivery.external_id, "performer_not_found")
      poll(ctx.branch)

      assert %Delivery{status: :failed, close_reason: :not_found} = Repo.reload!(ctx.delivery)
      assert %Delivery{status: :searching} = next = Couriers.active(ctx.order.id)
      assert next.id != ctx.delivery.id
      assert Agent.get(ctx.yandex, & &1.created) == 2
      refute_received {:yandex, "/claims/cancel", _query, _body}
    end

    test "stops calling after three lost claims", ctx do
      for _attempt <- 1..3 do
        delivery = Couriers.active(ctx.order.id)
        set_status(ctx.yandex, delivery.external_id, "performer_not_found")
        poll(ctx.branch)
      end

      assert Couriers.active(ctx.order.id) == nil
      assert Agent.get(ctx.yandex, & &1.created) == 3
    end

    test "a cancelled order cancels the claim", ctx do
      {:ok, _order} =
        Orders.cancel_order(Repo.reload!(ctx.order), {:staff, ctx.operator}, %{
          "cancel_reason" => "other"
        })

      deliver_events()

      assert_received {:yandex, "/claims/cancel", _query,
                       %{"cancel_state" => "free", "version" => 3}}

      assert %Delivery{status: :cancelled, close_reason: :order_cancelled} =
               Repo.reload!(ctx.delivery)
    end

    test "a claim cancelled at yandex closes the attempt", ctx do
      set_status(ctx.yandex, ctx.delivery.external_id, "cancelled")
      poll(ctx.branch)

      assert %Delivery{status: :cancelled, close_reason: :provider_cancelled} =
               Repo.reload!(ctx.delivery)

      refute_received {:yandex, "/claims/cancel", _query, _body}
    end

    test "a returning courier is flagged", ctx do
      set_status(ctx.yandex, ctx.delivery.external_id, "returning")
      poll(ctx.branch)

      assert YandexDelivery.returning?(Couriers.active(ctx.order.id))
    end
  end

  test "settings keep the token when it is left blank" do
    branch = branch()

    staff =
      insert(:staff, role: build(:role, permissions: ["integrations.update"]), branches: [branch])
      |> Repo.preload([:role, :branches])

    assert {:ok, %Settings{token: "y-token", taxi_class: :express}} =
             YandexDelivery.update_settings(staff, branch.id, %{
               "token" => "",
               "taxi_class" => "express"
             })

    assert {:error, %Ecto.Changeset{}} =
             YandexDelivery.update_settings(staff, branch.id, %{"contact_email" => "nope"})
  end
end
