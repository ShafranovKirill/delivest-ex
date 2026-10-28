defmodule DelivestWeb.Staff.IntegrationLive.YandexEdaTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory
  import Delivest.YandexEdaFixtures

  alias Delivest.Integrations.Channels.Products
  alias Delivest.Integrations.YandexEda

  defp sign_in(conn, branch, permissions) do
    staff = insert(:staff, role: insert(:role, permissions: permissions))
    insert(:staff_branch, staff: staff, branch: branch)
    init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
  end

  test "an admin generates access and sets up the branch", %{conn: conn} do
    branch = yandex_branch(enabled: false)

    {:ok, lv, _html} =
      live(
        sign_in(conn, branch, ["admin", "integrations.read", "integrations.update"]),
        ~p"/staff/b/#{branch}/integrations/yandex-eda"
      )

    refute has_element?(lv, "#yandex-eda-client-id")
    lv |> element("#yandex-eda-rotate") |> render_click()
    assert has_element?(lv, "#yandex-eda-client-id", YandexEda.get_settings().client_id)

    lv
    |> form("#yandex-eda-branch",
      yandex_eda: %{enabled: "true", accept_mode: "manual", markup_percent: "15", vat: "22"}
    )
    |> render_submit()

    assert %{enabled: true, accept_mode: :manual, markup_percent: 15, vat: 22} =
             YandexEda.get_branch_settings(branch.id)
  end

  test "products are switched off for the channel", %{conn: conn} do
    branch = yandex_branch()
    product = menu_product(branch, menu_category(branch))

    {:ok, lv, _html} =
      live(
        sign_in(conn, branch, ["integrations.read", "products.update"]),
        ~p"/staff/b/#{branch}/integrations/yandex-eda"
      )

    refute has_element?(lv, "#yandex-eda-access")

    lv
    |> form("#yandex-eda-product-#{product.id}")
    |> render_change(%{"product_id" => product.id, "enabled" => "false", "price" => "250"})

    assert %{enabled: false, price: 250} = Products.get(:yandex_eda, product.id)
  end

  test "a reader cannot change the branch", %{conn: conn} do
    branch = yandex_branch()

    {:ok, lv, _html} =
      live(
        sign_in(conn, branch, ["integrations.read"]),
        ~p"/staff/b/#{branch}/integrations/yandex-eda"
      )

    assert has_element?(lv, "#yandex_eda_enabled[disabled]")
  end

  test "a branch editor pauses the branch and lifts the pause", %{conn: conn} do
    push_credentials()
    branch = yandex_branch()

    stub_push(%{
      "/v2/status" => %{
        "items" => [
          %{
            "vendorId" => branch.id,
            "blockId" => "7",
            "deliveryType" => "ddc",
            "from" => "2026-10-27T12:00:00+03:00",
            "availableToCancel" => true
          }
        ]
      }
    })

    {:ok, lv, _html} =
      live(
        sign_in(conn, branch, ["integrations.read", "stops.update"]),
        ~p"/staff/b/#{branch}/integrations/yandex-eda"
      )

    assert render_async(lv) =~ "27.10 12:00"

    lv |> form("#yandex-eda-pause-form", minutes: "60", tag: "too_busy") |> render_submit()
    assert_received {:push, "/block", %{"tag" => "too_busy"}}

    lv |> element("#yandex-eda-pause-7 button") |> render_click()
    assert_received {:push, "/unblock", %{"blockIds" => ["7"]}}
  end

  test "without push access the pause is hidden", %{conn: conn} do
    branch = yandex_branch()

    {:ok, lv, _html} =
      live(
        sign_in(conn, branch, ["integrations.read"]),
        ~p"/staff/b/#{branch}/integrations/yandex-eda"
      )

    refute has_element?(lv, "#yandex-eda-pause")
  end

  test "orders are reconciled with the yandex history", %{conn: conn} do
    push_credentials()
    branch = yandex_branch()

    stub_push(%{
      "/v1/orders-history" => %{
        "orders" => [%{"eats_id" => "260427-lost", "status" => "NEW", "items_cost" => 450}]
      }
    })

    {:ok, lv, _html} =
      live(
        sign_in(conn, branch, ["integrations.read", "orders.read"]),
        ~p"/staff/b/#{branch}/integrations/yandex-eda"
      )

    lv
    |> form("#yandex-eda-reconcile", date: Date.to_iso8601(Date.utc_today()))
    |> render_submit()

    html = render_async(lv)

    assert html =~ "Orders in Yandex: 1, differences: 1"
    assert has_element?(lv, "#yandex-eda-reconciliation-260427-lost", "No such order here")
  end
end
