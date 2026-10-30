defmodule DelivestWeb.Staff.PosLive.IndexTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory
  import Delivest.YandexEdaFixtures, only: [menu_category: 1, menu_product: 3]

  alias Delivest.{Payments, Pos, Repo}
  alias Delivest.Oms.Order

  setup %{conn: conn} do
    branch = insert(:branch, is_active: true)

    cashier =
      insert(:staff, name: "Ольга", role: build(:role, permissions: ["orders.read", "pos.use"]))

    insert(:staff_branch, staff: cashier, branch: branch)
    product = menu_product(branch, menu_category(branch), price: 25_000)

    %{
      conn: init_test_session(conn, %{"staff_id" => cashier.id}),
      branch: branch,
      cashier: cashier,
      product: product
    }
  end

  test "the cashier sells for cash with change and the order goes to the kitchen", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/staff/b/#{ctx.branch}/pos")

    lv |> element("#pos-product-#{ctx.product.id}") |> render_click()
    lv |> element("#pos-product-#{ctx.product.id}") |> render_click()
    lv |> element("#pos-type-pickup") |> render_click()
    assert lv |> element("#pos-check-total") |> render() =~ "500"

    lv |> element("#pos-pay") |> render_click()
    lv |> form("#pos-cash", %{cash: "1000"}) |> render_change()
    assert lv |> element("#pos-change") |> render() =~ "500"

    lv |> element("#pos-confirm") |> render_click()
    assert lv |> element("#pos-done-change") |> render() =~ "500"

    assert [%Order{source: "pos", status: :accepted, fulfillment_type: :pickup} = order] =
             Repo.all(Order)

    assert [%{method: :cash, status: :paid, amount: 50_000, cash_given: 100_000}] =
             Payments.list(order.id)

    lv |> element("#pos-next") |> render_click()
    assert lv |> element("#pos-check-total") |> render() =~ "0"

    order |> Ecto.Changeset.change(status: :ready) |> Repo.update!()
    assert [_ready] = Pos.ready(ctx.branch.id)
    send(lv.pid, {Delivest.Oms.Orders, [:order, :updated], order})

    lv |> element("#pos-tab-handout") |> render_click()
    lv |> element("#pos-ready-#{order.id}") |> render_click()
    assert Repo.reload!(order).status == :completed
  end

  test "card payment needs no cash", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/staff/b/#{ctx.branch}/pos")
    lv |> element("#pos-product-#{ctx.product.id}") |> render_click()
    lv |> element("#pos-pay") |> render_click()
    lv |> element("#pos-method-card") |> render_click()
    lv |> element("#pos-confirm") |> render_click()

    assert [%Order{fulfillment_type: :dine_in} = order] = Repo.all(Order)
    assert [%{method: :card, status: :paid}] = Payments.list(order.id)
  end

  test "staff without the pos permission is turned away", ctx do
    staff = insert(:staff, role: build(:role, permissions: ["orders.read"]))
    insert(:staff_branch, staff: staff, branch: ctx.branch)
    conn = init_test_session(ctx.conn, %{"staff_id" => staff.id})
    assert {:error, {_kind, _redirect}} = live(conn, ~p"/staff/b/#{ctx.branch}/pos")
  end
end
