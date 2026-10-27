defmodule Delivest.Integrations.YandexEda.OrderConfirmationTest do
  use Delivest.DataCase, async: true
  use Oban.Testing, repo: Delivest.Repo

  import Delivest.Factory
  import Delivest.YandexEdaFixtures

  alias Delivest.Integrations.YandexEda
  alias Delivest.Integrations.YandexEda.AcceptDeadlineWorker
  alias Delivest.Oms.{Order, Orders}

  setup do
    branch = yandex_branch(accept_mode: :manual, accept_minutes: 10)
    product = menu_product(branch, menu_category(branch))
    {:ok, order} = YandexEda.create_order(order_params(branch, [product]))
    staff = insert(:staff, role: build(:role, permissions: ["orders.read", "orders.update"]))
    %{branch: branch, order: order, staff: staff}
  end

  defp overdue!(order) do
    past = DateTime.utc_now(:second) |> DateTime.add(-1, :minute) |> DateTime.to_iso8601()

    {:ok, order} =
      Orders.update_order_channel(order, %{
        details: Map.put(order.channel.details, "accept_by", past)
      })

    order
  end

  test "the deadline is watched and the order is not overdue before it", %{
    branch: branch,
    order: order
  } do
    assert_enqueued(worker: AcceptDeadlineWorker, args: %{"order_id" => order.id})
    assert YandexEda.overdue_orders(branch.id) == []

    overdue!(order)
    assert [%Order{id: id}] = YandexEda.overdue_orders(branch.id)
    assert id == order.id
  end

  test "the deadline wakes the staff pages up", %{branch: branch, order: order} do
    Orders.subscribe_branch(branch.id)

    assert :ok = perform_job(AcceptDeadlineWorker, %{"order_id" => order.id})
    assert_receive {:branch_orders_changed, branch_id}
    assert branch_id == branch.id
  end

  test "let it wait hides the alert but keeps the order new", ctx do
    overdue!(ctx.order)

    assert {:ok, _} = YandexEda.keep_unconfirmed(ctx.staff, ctx.branch.id, ctx.order.id)
    assert YandexEda.overdue_orders(ctx.branch.id) == []
    assert Repo.get!(Order, ctx.order.id).status == :created
  end

  test "confirm accepts the order", ctx do
    overdue!(ctx.order)

    assert {:ok, %Order{status: :accepted}} =
             YandexEda.confirm_unconfirmed(ctx.staff, ctx.branch.id, ctx.order.id)

    assert {:ok, %{status: "ACCEPTED_BY_RESTAURANT"}} = YandexEda.order_status(ctx.order.id)
  end

  test "cancel cancels as not confirmed in time", ctx do
    overdue!(ctx.order)

    assert {:ok, %Order{status: :cancelled, cancel_reason: :not_confirmed}} =
             YandexEda.cancel_unconfirmed(ctx.staff, ctx.branch.id, ctx.order.id)

    assert {:ok, %{status: "CANCELLED"}} = YandexEda.order_status(ctx.order.id)
  end

  test "only staff with order rights act and only on new orders of the branch", ctx do
    reader = insert(:staff, role: build(:role, permissions: ["orders.read"]))

    assert {:error, :forbidden} =
             YandexEda.confirm_unconfirmed(reader, ctx.branch.id, ctx.order.id)

    assert {:error, :order_not_found} =
             YandexEda.confirm_unconfirmed(ctx.staff, Ecto.UUID.generate(), ctx.order.id)

    {:ok, _} = YandexEda.confirm_unconfirmed(ctx.staff, ctx.branch.id, ctx.order.id)

    assert {:error, :order_not_found} =
             YandexEda.cancel_unconfirmed(ctx.staff, ctx.branch.id, ctx.order.id)
  end

  test "auto mode does not watch the deadline" do
    branch = yandex_branch()
    product = menu_product(branch, menu_category(branch))
    {:ok, order} = YandexEda.create_order(order_params(branch, [product]))

    refute_enqueued(worker: AcceptDeadlineWorker, args: %{"order_id" => order.id})
  end
end
