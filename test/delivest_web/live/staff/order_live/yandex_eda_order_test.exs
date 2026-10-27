defmodule DelivestWeb.Staff.OrderLive.YandexEdaOrderTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory
  import Delivest.YandexEdaFixtures

  alias Delivest.Integrations.YandexEda

  test "the order card shows the yandex courier", %{conn: conn} do
    branch = yandex_branch()
    product = menu_product(branch, menu_category(branch))
    {:ok, order} = YandexEda.create_order(order_params(branch, [product]))

    {:ok, _} =
      YandexEda.update_courier(order.id, %{
        "courier" => %{"name" => "Василий", "phone" => "+79031111111", "status" => "accepted"},
        "maxPlaceArrivalTime" => "2026-10-27T12:10:00.000000+03:00"
      })

    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    {:ok, lv, _html} = live(conn, ~p"/staff/orders")

    assert has_element?(lv, "#order-courier-#{order.id}", "Василий")
    assert has_element?(lv, "#order-courier-#{order.id}", "+79031111111")
    assert has_element?(lv, "#order-courier-#{order.id}", "12:10")
    assert has_element?(lv, "#order-source-#{order.id}")
  end
end
