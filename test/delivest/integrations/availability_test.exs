defmodule Delivest.Integrations.AvailabilityTest do
  use Delivest.DataCase, async: true
  use Oban.Testing, repo: Delivest.Repo

  import Delivest.Factory

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.{Availability, Crm, Frontpad, Poller}
  alias Delivest.Integrations.Crm.{BranchSettings, CatalogPoller, SyncState, SyncWorker}
  alias Delivest.Oms.Carts
  alias Delivest.Oms

  defp branch do
    branch = insert(:branch, is_active: true)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{
        enabled: true,
        provider: :frontpad,
        frontpad: %Frontpad.Settings{api_key: "key", webhook_token: "hook-#{branch.id}"}
      }
    })

    branch
  end

  defp order(branch) do
    product = insert_branch_product(branch.id, price: 100, external_id: "1")
    {:ok, cart} = Carts.create_cart(%{session_id: "crm-#{branch.id}", branch_id: branch.id})
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

  defp actor(branch) do
    insert(:staff,
      role: insert(:role, permissions: ["integrations.update", "orders.update"]),
      branches: [branch]
    )
  end

  defp args(order) do
    %{
      "order_id" => order.id,
      "branch_id" => order.branch_id,
      "generation" => Availability.crm(order.branch_id, :frontpad).generation
    }
  end

  test "disabled branch creates no new CRM job and stale queued work cannot send after re-enable" do
    branch = branch()
    order = order(branch)
    old = args(order)
    staff = actor(branch)

    assert {:ok, _} = Crm.update_branch_settings(staff, branch.id, %{"enabled" => false})
    Req.Test.stub(Delivest.HTTP.Client, fn _ -> flunk("disabled CRM called Frontpad") end)

    assert {:ok, :disabled} = Crm.enqueue_sync(order)
    assert {:cancel, :disabled} = perform_job(SyncWorker, old)
    assert Repo.reload!(order).crm.status == "failed"

    assert {:ok, _} = Crm.update_branch_settings(staff, branch.id, %{"enabled" => true})
    assert {:cancel, :order_not_pending} = perform_job(SyncWorker, old)
    refute Availability.crm_allowed?(branch.id, :frontpad, :orders, old["generation"])
    assert {:ok, retried} = Crm.resolve_alert(staff, branch.id, order.id, "retry_unsent")
    assert retried.crm.status == "pending"

    assert_enqueued(
      worker: SyncWorker,
      args: %{
        "order_id" => order.id,
        "generation" => Availability.crm(branch.id, :frontpad).generation
      }
    )
  end

  test "the atomic delivery claim rejects a generation changed after an earlier readiness check" do
    branch = branch()
    order = order(branch)
    old = args(order)
    staff = actor(branch)
    assert Availability.crm_allowed?(branch.id, :frontpad, :orders, old["generation"])

    assert {:ok, _} = Crm.update_branch_settings(staff, branch.id, %{"enabled" => false})
    Req.Test.stub(Delivest.HTTP.Client, fn _ -> flunk("stale claim called Frontpad") end)
    assert {:error, :disabled} = SyncState.claim_sending(order, 1, old["generation"])
    assert %{status: "failed", alert: alert} = Repo.reload!(order).crm
    assert alert =~ "not sent"
  end

  test "a stale worker cannot mark another worker's started request as unsent" do
    branch = branch()
    stale_order = order(branch)
    generation = args(stale_order)["generation"]

    assert {:ok, sending} = SyncState.claim_sending(stale_order, 1, generation)
    assert sending.crm.status == "sending"
    assert :already_started = SyncState.fail_if_pending(stale_order, 1)
    assert %{status: "sending", alert: nil} = Repo.reload!(stale_order).crm
  end

  test "a failed unresolved order remains in the unsent obligation count" do
    branch = branch()
    order = order(branch)
    assert {:ok, _} = SyncState.failed(order, "permanent provider rejection", 1)
    assert %{unsent: 1} = Crm.work_summary(branch.id)["frontpad"]
  end

  test "turning off one branch leaves the enabled neighbour available" do
    first = branch()
    second = branch()
    staff = actor(first)

    assert {:ok, _} = Crm.update_branch_settings(staff, first.id, %{"enabled" => false})
    refute Availability.crm_allowed?(first.id, :frontpad, :orders)
    assert Availability.crm_allowed?(second.id, :frontpad, :orders)
  end

  test "consecutive catalog ticks exclude a disabled branch and keep its neighbour" do
    first = branch()
    second = branch()
    staff = actor(first)
    assert {:ok, _} = Crm.update_branch_settings(staff, first.id, %{"enabled" => false})
    Req.Test.stub(Delivest.HTTP.Client, fn _ -> flunk("producer must not call Frontpad") end)

    for _tick <- 1..3 do
      assert :ok = Poller.enqueue_all(CatalogPoller)
      refute first.id in CatalogPoller.targets()
      assert second.id in CatalogPoller.targets()
    end

    jobs = Repo.all(Oban.Job) |> Enum.filter(&(&1.args["poller"] == "crm_catalog"))
    refute Enum.any?(jobs, &(&1.args["target"] == first.id))
    assert Enum.any?(jobs, &(&1.args["target"] == second.id))
  end

  test "switching off cancels a queued job and exposes a manual unsent retry" do
    branch = branch()
    order = order(branch)
    staff = actor(branch)
    {:ok, job} = Crm.enqueue_sync(order)

    assert {:ok, _} = Crm.update_branch_settings(staff, branch.id, %{"enabled" => false})
    assert Crm.get_branch_settings(branch.id).generation == 1
    assert Repo.get!(Oban.Job, job.id).state == "cancelled"
    assert %{status: "pending", alert: alert} = Repo.reload!(order).crm
    assert alert =~ "not sent"
    assert {:error, :disabled} = Crm.resolve_alert(staff, branch.id, order.id, "retry_unsent")

    assert {:ok, _} = Crm.update_branch_settings(staff, branch.id, %{"enabled" => true})
    assert Repo.reload!(order).crm.status == "pending"
    assert {:ok, _} = Crm.resolve_alert(staff, branch.id, order.id, "retry_unsent")
    assert_enqueued(worker: SyncWorker, args: %{"order_id" => order.id, "generation" => 2})
  end
end
