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

  test "staff checks the yandex courier code", %{conn: conn} do
    push_credentials()
    branch = yandex_branch()
    product = menu_product(branch, menu_category(branch))
    {:ok, order} = YandexEda.create_order(order_params(branch, [product]))
    {:ok, _} = YandexEda.update_courier(order.id, %{"courier" => %{"name" => "Василий"}})

    test_pid = self()

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case conn.request_path do
        "/oauth2/token" ->
          Req.Test.json(conn, %{"access_token" => "push", "expires_in" => 3600})

        path ->
          send(test_pid, {:push, path, Jason.decode!(body)})

          case Jason.decode!(body) do
            %{"code" => "1234"} ->
              Req.Test.json(conn, %{"is_valid" => true})

            %{"code" => "0000"} ->
              Req.Test.json(conn, %{"is_valid" => false, "validation_attempts_left" => 1})

            _ ->
              conn
              |> Plug.Conn.put_status(409)
              |> Req.Test.json(%{"code" => 1001, "message" => "no"})
          end
      end
    end)

    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
    {:ok, lv, _html} = live(conn, ~p"/staff/orders")
    form = "#order-courier-code-#{order.id}"

    assert lv |> form(form, code: " 1234 ") |> render_submit() =~ "The courier code is correct"
    path = "/platform/orders/#{order.id}/codes/validate"
    assert_received {:push, ^path, %{"code" => "1234"}}

    assert lv |> form(form, code: "0000") |> render_submit() =~ "attempts left: 1"

    assert lv |> form(form, code: "9999") |> render_submit() =~
             "No attempts left to check the courier code"

    assert lv |> form(form, code: "") |> render_submit() =~ "Enter the courier code"
  end
end
