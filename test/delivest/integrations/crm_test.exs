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
    Repo.insert!(%BranchInfo{branch_id: branch.id, crm: crm})
    branch
  end

  defp frontpad(enabled?) do
    %BranchSettings{
      enabled: enabled?,
      provider: :frontpad,
      frontpad: %Frontpad.Settings{api_key: "key", affiliate: "3"}
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
end
