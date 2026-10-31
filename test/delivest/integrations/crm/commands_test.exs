defmodule Delivest.Integrations.Crm.CommandsTest do
  use Delivest.DataCase, async: true
  use Oban.Testing, repo: Delivest.Repo

  import Delivest.Factory

  alias Delivest.Events.Event
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Crm

  alias Delivest.Integrations.Crm.{
    BranchSettings,
    CommandWorker,
    ConfirmWorker,
    OrderSubscriber,
    SyncWorker
  }

  alias Delivest.Integrations.{Frontpad, TestCrm}
  alias Delivest.Oms
  alias Delivest.Oms.{Carts, Order, Orders}

  setup do
    branch = insert(:branch, is_active: true)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{
        enabled: true,
        provider: :test_crm,
        test_crm: %TestCrm.Settings{token: "t"}
      }
    })

    product = insert_branch_product(branch.id, price: 100)
    {:ok, cart} = Carts.create_cart(%{session_id: "cmd-#{branch.id}", branch_id: branch.id})
    {:ok, _, _} = Carts.add_item(cart.id, product.id, 1)

    {:ok, order} =
      Oms.create_order(%{
        "cart_id" => cart.id,
        "branch_id" => branch.id,
        "fulfillment_type" => "pickup",
        "payment_method" => "cash"
      })

    %{order: order}
  end

  defp sync(order),
    do: perform_job(SyncWorker, %{"order_id" => order.id, "branch_id" => order.branch_id})

  defp sent(order) do
    :ok = sync(order)
    Orders.get_order(order.id)
  end

  test "providers report capabilities and idempotency" do
    assert Crm.capabilities(:frontpad) == []
    refute Crm.idempotent?(:frontpad)
    assert :cancel in Crm.capabilities(:test_crm)
    assert Crm.idempotent?(:test_crm)
    assert Crm.status_for(:test_crm, nil, 9) == :cancelled

    assert Crm.status_for(
             :frontpad,
             %Frontpad.Settings{statuses: %Frontpad.StatusCodes{ready: "3"}},
             "3"
           ) ==
             :ready
  end

  test "dictionaries come from the active provider", %{order: order} do
    assert {:ok, %{payment_types: [%{id: "cash"}]}} = Crm.dictionaries(order.branch_id)
  end

  test "a pending creation waits for confirmation", %{order: order} do
    Process.put({TestCrm, :deliver}, {:pending, "ref-1"})
    :ok = sync(order)

    order = Orders.get_order(order.id)
    assert %{status: "confirming", ref: "ref-1"} = order.crm
    assert order.status == :created
    assert_enqueued(worker: ConfirmWorker, args: %{"order_id" => order.id})

    assert {:ok, %Order{status: :accepted, crm: %{status: "sent", external_id: "e-9"}}} =
             Crm.confirm_order(order, %{external_id: "e-9"})
  end

  test "an unconfirmed idempotent creation is sent again", %{order: order} do
    Process.put({TestCrm, :deliver}, {:pending, "ref-1"})
    :ok = sync(order)

    :ok = perform_job(ConfirmWorker, %{"order_id" => order.id})
    assert %{status: "pending"} = Orders.get_order(order.id).crm
    assert_enqueued(worker: SyncWorker, args: %{"order_id" => order.id})
  end

  test "a rejected creation fails the sync", %{order: order} do
    Process.put({TestCrm, :deliver}, {:pending, "ref-1"})
    :ok = sync(order)

    assert {:ok, %Order{crm: %{status: "failed", last_error: "bad"}}} =
             Crm.reject_order(Orders.get_order(order.id), "bad")
  end

  test "a cancel goes to a crm that can cancel", %{order: order} do
    order = sent(order)
    {:ok, _order} = Orders.cancel_order(order, :system, %{"cancel_reason" => "out_of_stock"})
    deliver_events()

    assert_enqueued(worker: CommandWorker, args: %{"action" => "cancel", "order_id" => order.id})

    assert :ok =
             perform_job(CommandWorker, %{
               "order_id" => order.id,
               "action" => "cancel",
               "reason" => "out_of_stock"
             })

    assert_received {:cancel, _id, :out_of_stock}
    refute Crm.manual_cancel_required?(%{order | channel: %{remote_status: "cancelled"}})
  end

  test "only allowed changes go to the crm", %{order: order} do
    order = sent(order)

    event = %Event{
      type: "order.updated",
      aggregate_id: order.id,
      actor: %{"kind" => "staff"},
      payload: %{
        "changes" => %{
          "comment" => %{"from" => nil, "to" => "x"},
          "items" => %{"from" => [], "to" => []}
        }
      }
    }

    {:ok, _job} = OrderSubscriber.handle(event)

    assert_enqueued(
      worker: CommandWorker,
      args: %{"action" => "update", "changes" => %{"comment" => %{"from" => nil, "to" => "x"}}}
    )

    assert :ok = OrderSubscriber.handle(%{event | actor: %{"kind" => "crm"}})
  end

  test "failed commands stop on permanent errors", %{order: order} do
    order = sent(order)
    Process.put({TestCrm, :update}, {:error, :rejected})

    assert {:cancel, :rejected} =
             perform_job(CommandWorker, %{
               "order_id" => order.id,
               "action" => "update",
               "changes" => %{}
             })
  end
end
