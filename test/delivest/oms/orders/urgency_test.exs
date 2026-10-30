defmodule Delivest.Oms.Orders.UrgencyTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Oms.{Carts, OrderDeadline, Orders}

  setup do
    branch = insert(:branch, is_active: true)
    Repo.insert!(%BranchInfo{branch_id: branch.id, delivery_time: 40})
    product = insert_branch_product(branch.id, price: 100)
    %{branch: branch, product: product}
  end

  defp order(%{branch: branch, product: product}, minutes_ago, changes) do
    {:ok, cart} = Carts.create_cart(%{session_id: Ecto.UUID.generate(), branch_id: branch.id})
    {:ok, _, _} = Carts.add_item(cart.id, product.id, 1)

    {:ok, order} =
      Orders.create_order(%{
        "cart_id" => cart.id,
        "branch_id" => branch.id,
        "fulfillment_type" => "pickup",
        "payment_method" => "cash"
      })

    inserted_at = DateTime.add(DateTime.utc_now(:second), -minutes_ago, :minute)
    order |> Ecto.Changeset.change([inserted_at: inserted_at] ++ changes) |> Repo.update!()
  end

  test "new orders lead, then the closest deadline, finished ones go last", ctx do
    in_two_hours =
      DateTime.utc_now(:second) |> DateTime.add(2, :hour)

    finished = order(ctx, 50, status: :completed)
    pickup = order(ctx, 5, status: :preparing)
    delivery = order(ctx, 30, status: :preparing, fulfillment_type: :delivery)
    planned = order(ctx, 1, status: :preparing, cook_by: in_two_hours)
    fresh = order(ctx, 0, [])

    {:ok, {orders, _meta}} = Orders.paginate_orders(%{branch_id: ctx.branch.id}, %{})

    assert Enum.map(orders, & &1.id) ==
             Enum.map([fresh, delivery, pickup, planned, finished], & &1.id)

    {:ok, {by_time, _meta}} =
      Orders.paginate_orders(%{branch_id: ctx.branch.id, sort: "time"}, %{})

    assert Enum.map(by_time, & &1.id) ==
             Enum.map([fresh, planned, pickup, delivery, finished], & &1.id)
  end

  test "counts and filters use the crm status when the crm runs the order", ctx do
    order(ctx, 0, [])
    order(ctx, 0, status: :preparing)

    crm =
      order(ctx, 0, [])
      |> Ecto.Changeset.change(crm: %{provider: "frontpad", status: "sent", remote_status: nil})
      |> Repo.update!()

    {:ok, crm} = Delivest.Integrations.Crm.SyncState.remote_status(crm, :preparing, "3", nil)

    assert %{created: 1, preparing: 2} = Orders.count_by_status(%{branch_id: ctx.branch.id})

    {:ok, {preparing, _meta}} =
      Orders.paginate_orders(%{branch_id: ctx.branch.id, status: "preparing"}, %{})

    assert crm.id in Enum.map(preparing, & &1.id)
    assert length(preparing) == 2
  end

  test "the deadline is the requested time or the creation time plus the lead", ctx do
    pickup = order(ctx, 0, [])
    assert OrderDeadline.at(pickup, 40) == DateTime.add(pickup.inserted_at, 20, :minute)
    assert OrderDeadline.lead_minutes(:delivery, 40) == 40
    assert OrderDeadline.lead_minutes(:pickup, 90) == 45
  end

  test "the problem filter keeps overdue orders and crm trouble", ctx do
    on_time = order(ctx, 5, status: :preparing)
    overdue = order(ctx, 100, status: :preparing)
    finished_late = order(ctx, 100, status: :completed)

    alerted =
      order(ctx, 5,
        status: :accepted,
        crm: %Delivest.Oms.Order.CrmSync{provider: "frontpad", status: "sent", alert: "check"}
      )

    failed =
      order(ctx, 5,
        status: :accepted,
        crm: %Delivest.Oms.Order.CrmSync{provider: "frontpad", status: "failed"}
      )

    {:ok, {orders, _meta}} =
      Orders.paginate_orders(%{branch_id: ctx.branch.id, problem: true}, %{})

    ids = Enum.map(orders, & &1.id)
    assert Enum.sort(ids) == Enum.sort([overdue.id, alerted.id, failed.id])
    refute on_time.id in ids
    refute finished_late.id in ids
  end
end
