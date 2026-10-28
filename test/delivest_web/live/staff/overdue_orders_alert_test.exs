defmodule DelivestWeb.Staff.OverdueOrdersAlertTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory
  import Delivest.YandexEdaFixtures

  alias Delivest.Integrations.YandexEda
  alias Delivest.Oms.{Order, Orders}
  alias Delivest.Oms.Orders.Notifier
  alias Delivest.Repo

  setup %{conn: conn} do
    branch = yandex_branch(accept_mode: :manual)
    product = menu_product(branch, menu_category(branch))
    {:ok, order} = YandexEda.create_order(order_params(branch, [product]))

    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    %{conn: conn, branch: branch, order: order}
  end

  defp overdue!(order) do
    past = DateTime.utc_now(:second) |> DateTime.add(-1, :minute) |> DateTime.to_iso8601()
    details = Map.put(order.channel.details, "accept_by", past)
    {:ok, _order} = Orders.update_order_channel(order, %{details: details})
  end

  test "the alert pops up on any page once the deadline passes", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/staff/b/#{ctx.branch}/integrations")
    refute has_element?(lv, "#overdue-orders")

    overdue!(ctx.order)
    Notifier.branch_changed(ctx.branch.id)

    assert has_element?(lv, "#overdue-order-#{ctx.order.id}", ctx.order.channel.external_id)
  end

  test "confirm from the alert accepts the order", ctx do
    overdue!(ctx.order)
    {:ok, lv, _html} = live(ctx.conn, ~p"/staff/b/#{ctx.branch}/orders")

    lv |> element("#overdue-confirm-#{ctx.order.id}") |> render_click()

    refute has_element?(lv, "#overdue-orders")
    assert Repo.get!(Order, ctx.order.id).status == :accepted
  end

  test "cancel from the alert cancels the order", ctx do
    overdue!(ctx.order)
    {:ok, lv, _html} = live(ctx.conn, ~p"/staff/b/#{ctx.branch}/orders")

    lv |> element("#overdue-cancel-#{ctx.order.id}") |> render_click()

    assert %Order{status: :cancelled, cancel_reason: :not_confirmed} =
             Repo.get!(Order, ctx.order.id)
  end

  test "let it wait closes the alert and keeps the order new", ctx do
    overdue!(ctx.order)
    {:ok, lv, _html} = live(ctx.conn, ~p"/staff/b/#{ctx.branch}/integrations")

    lv |> element("#overdue-keep-#{ctx.order.id}") |> render_click()

    refute has_element?(lv, "#overdue-orders")
    assert Repo.get!(Order, ctx.order.id).status == :created
  end
end
