defmodule Delivest.Integrations.Crm.FrontpadStopOrderTriggerTest do
  use Delivest.DataCase, async: false
  use Oban.Testing, repo: Delivest.Repo

  import Delivest.Factory

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Crm.{BranchSettings, SyncWorker}
  alias Delivest.Integrations.Crm.FrontpadStopRefresh.RefreshJob
  alias Delivest.Integrations.Frontpad
  alias Delivest.Oms
  alias Delivest.Oms.Carts

  defp order do
    branch = insert(:branch, is_active: true)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{
        enabled: true,
        provider: :frontpad,
        frontpad: %Frontpad.Settings{api_key: "key", affiliate: "3", sync_stops: true}
      }
    })

    product = insert_branch_product(branch.id, price: 100, external_id: "fp-1")
    {:ok, cart} = Carts.create_cart(%{session_id: "p4-#{branch.id}", branch_id: branch.id})
    {:ok, _, _} = Carts.add_item(cart.id, product.id, 1)

    {:ok, order} =
      Oms.create_order(%{
        "cart_id" => cart.id,
        "branch_id" => branch.id,
        "fulfillment_type" => "pickup",
        "payment_method" => "cash"
      })

    order
  end

  test "only exact new_order invalid_product_keys failure queues a stop refresh" do
    order = order()
    test_pid = self()

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      send(test_pid, {:frontpad_call, conn.query_string})
      Req.Test.json(conn, %{"result" => "error", "error" => "invalid_product_keys"})
    end)

    assert {:cancel, {:frontpad, "invalid_product_keys"}} =
             perform_job(SyncWorker, %{"order_id" => order.id, "branch_id" => order.branch_id})

    assert_received {:frontpad_call, "new_order"}
    refute_received {:frontpad_call, "get_stops"}
    assert_enqueued(worker: RefreshJob, queue: :polling, args: %{"branch_id" => order.branch_id})
    assert Repo.reload!(order).crm.status == "failed"
  end

  for {name, response} <- [
        {"successful order warning",
         %{
           "result" => "success",
           "order_id" => "12",
           "warnings" => %{"invalid_product_keys" => [0]}
         }},
        {"authentication error", %{"result" => "error", "error" => "invalid_secret"}},
        {"other business error", %{"result" => "error", "error" => "invalid_plant"}}
      ] do
    test "#{name} does not queue a stop refresh" do
      order = order()
      Req.Test.stub(Delivest.HTTP.Client, &Req.Test.json(&1, unquote(Macro.escape(response))))
      _ = perform_job(SyncWorker, %{"order_id" => order.id, "branch_id" => order.branch_id})
      refute_enqueued(worker: RefreshJob)
    end
  end

  test "network error does not queue a stop refresh" do
    order = order()
    Req.Test.stub(Delivest.HTTP.Client, &Req.Test.transport_error(&1, :econnrefused))

    assert {:error, _reason} =
             perform_job(SyncWorker, %{"order_id" => order.id, "branch_id" => order.branch_id})

    refute_enqueued(worker: RefreshJob)
  end
end
