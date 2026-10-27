defmodule Delivest.Integrations.CrmTest do
  use Delivest.DataCase, async: true
  use Oban.Testing, repo: Delivest.Repo

  import Delivest.Factory

  alias Delivest.Audit.Event
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Crm.{BranchSettings, SyncWorker}
  alias Delivest.Integrations.Frontpad
  alias Delivest.Oms
  alias Delivest.Oms.{Carts, Order}

  defp branch(crm) do
    branch = insert(:branch, is_active: true)
    crm = put_in(crm.frontpad.webhook_token, "token-#{branch.id}")
    Repo.insert!(%BranchInfo{branch_id: branch.id, crm: crm})
    branch
  end

  defp frontpad(enabled?) do
    %BranchSettings{
      enabled: enabled?,
      provider: :frontpad,
      frontpad: %Frontpad.Settings{
        api_key: "key",
        affiliate: "3",
        webhook_token: "hook-token",
        statuses: %Frontpad.StatusCodes{preparing: "2", delivering: "4", completed: "5"}
      }
    }
  end

  defp place_order(branch, product_attrs \\ [external_id: "fp-1"]) do
    product = insert_branch_product(branch.id, [price: 100] ++ product_attrs)
    {:ok, cart} = Carts.create_cart(%{session_id: "crm-#{branch.id}", branch_id: branch.id})
    {:ok, _, _} = Carts.add_item(cart.id, product.id, 1)

    Oms.create_order(%{
      "cart_id" => cart.id,
      "branch_id" => branch.id,
      "fulfillment_type" => "pickup",
      "payment_method" => "cash"
    })
  end

  defp stub_frontpad(response),
    do: Req.Test.stub(Delivest.HTTP.Client, &Req.Test.json(&1, response))

  defp sync(order),
    do: perform_job(SyncWorker, %{"order_id" => order.id, "branch_id" => order.branch_id})

  test "branch without crm keeps orders in the app" do
    assert {:ok, %Order{status: :created, crm: nil}} = place_order(branch(frontpad(false)))
    refute_enqueued(worker: SyncWorker)
  end

  test "crm branch hands the order to the chosen crm in the same transaction" do
    assert {:ok, %Order{status: :crm} = order} = place_order(branch(frontpad(true)))
    assert %{provider: "frontpad", status: "pending"} = order.crm
    assert_enqueued(worker: SyncWorker, queue: :crm, args: %{"order_id" => order.id})
  end

  test "successful delivery stores the crm order id, number and warnings" do
    {:ok, order} = place_order(branch(frontpad(true)))

    stub_frontpad(%{
      "result" => "success",
      "order_id" => "555",
      "order_number" => "143",
      "warnings" => %{"invalid_datetime" => "too_long_period"}
    })

    assert :ok = sync(order)

    assert %{
             status: "sent",
             external_id: "555",
             external_number: "143",
             warnings: %{"invalid_datetime" => "too_long_period"},
             attempts: 1
           } = Repo.reload!(order).crm

    assert [%Event{action: "order.sent_to_crm"}] =
             Repo.all(from(e in Event, where: e.action == "order.sent_to_crm"))
  end

  test "temporary crm errors are retried" do
    {:ok, order} = place_order(branch(frontpad(true)))
    stub_frontpad(%{"result" => "error", "error" => "busy"})

    assert {:error, {:frontpad, "busy"}} = sync(order)
    assert %{status: "pending", attempts: 1, last_error: last_error} = Repo.reload!(order).crm
    assert last_error =~ "busy"
  end

  test "rate limit and closed shift postpone the delivery" do
    {:ok, order} = place_order(branch(frontpad(true)))

    stub_frontpad(%{"result" => "error", "error" => "requests_limit"})
    assert {:snooze, 60} = sync(order)

    stub_frontpad(%{"result" => "error", "error" => "cash_close"})
    assert {:snooze, 600} = sync(order)
    assert %{status: "pending"} = Repo.reload!(order).crm
  end

  test "invalid credentials fail the delivery at once" do
    {:ok, order} = place_order(branch(frontpad(true)))
    stub_frontpad(%{"result" => "error", "error" => "invalid_secret"})

    assert {:cancel, {:frontpad, "invalid_secret"}} = sync(order)
    assert %{status: "failed"} = Repo.reload!(order).crm
  end

  test "permanent crm errors stop retries" do
    {:ok, order} = place_order(branch(frontpad(true)), external_id: nil)

    assert {:cancel, {:missing_external_id, _}} = sync(order)
    assert %{status: "failed"} = Repo.reload!(order).crm
  end

  describe "status webhook" do
    alias Delivest.Integrations.Frontpad.Webhook
    alias Delivest.Oms.OrderStatus

    defp sent_order(branch) do
      {:ok, order} = place_order(branch)
      stub_frontpad(%{"result" => "success", "order_id" => "900"})
      :ok = sync(order)
      Repo.reload!(order)
    end

    test "maps the crm status code to the order status" do
      branch = branch(frontpad(true))
      order = sent_order(branch)

      assert {:ok, updated} =
               Webhook.change_status("token-#{branch.id}", 900, 4, "2026-10-20 12:03:00")

      assert OrderStatus.current(updated) == :delivering
      assert updated.crm.remote_status_code == "4"
      assert updated.crm.remote_status_at == ~U[2026-10-20 09:03:00Z]

      assert [%Event{}] =
               Repo.all(from(e in Event, where: e.action == "order.crm_status_changed"))

      assert OrderStatus.current(order) == :accepted
    end

    test "an order handed to the crm counts as confirmed" do
      branch = branch(frontpad(true))
      {:ok, order} = place_order(branch)
      assert OrderStatus.current(order) == :created

      stub_frontpad(%{"result" => "success", "order_id" => "900"})
      :ok = sync(order)
      assert OrderStatus.current(Repo.reload!(order)) == :accepted
    end

    test "completed crm orders stop being active" do
      branch = branch(frontpad(true))
      sent_order(branch)

      {:ok, updated} = Webhook.change_status("token-#{branch.id}", "900", "5", nil)
      refute OrderStatus.active?(updated)
    end

    test "unknown codes keep the previous status" do
      branch = branch(frontpad(true))
      sent_order(branch)

      assert {:ok, updated} = Webhook.change_status("token-#{branch.id}", "900", "99", nil)
      assert OrderStatus.current(updated) == :accepted
      assert updated.crm.remote_status_code == "99"
    end

    test "crm statuses never move back and unmapped codes keep the status" do
      branch = branch(frontpad(true))
      sent_order(branch)
      token = "token-#{branch.id}"

      {:ok, _} = Webhook.change_status(token, "900", "4", nil)
      {:ok, updated} = Webhook.change_status(token, "900", "2", nil)
      assert OrderStatus.current(updated) == :delivering

      {:ok, updated} = Webhook.change_status(token, "900", "99", nil)
      assert OrderStatus.current(updated) == :delivering
    end

    test "a wrong token finds nothing" do
      sent_order(branch(frontpad(true)))
      assert {:error, :not_found} = Webhook.change_status("wrong", "900", "4", nil)
    end

    test "new orders ask Frontpad for the configured status hooks" do
      branch = branch(frontpad(true))
      {:ok, order} = place_order(branch)
      test_pid = self()

      Req.Test.stub(Delivest.HTTP.Client, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:params, URI.decode_query(body)})
        Req.Test.json(conn, %{"result" => "success", "order_id" => "1"})
      end)

      :ok = sync(order)

      assert_receive {:params, params}
      hooks = for {"hook_status[" <> _, code} <- params, do: code
      assert Enum.sort(hooks) == ["2", "4", "5"]
      assert params["hook_url"] =~ "/integrations/crm/frontpad/token-#{branch.id}"
    end
  end
end
