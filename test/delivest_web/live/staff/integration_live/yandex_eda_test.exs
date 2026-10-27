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
        sign_in(conn, branch, ["admin", "branches.read", "branches.update"]),
        ~p"/staff/integrations/yandex-eda"
      )

    refute has_element?(lv, "#yandex-eda-client-id")
    lv |> element("#yandex-eda-rotate") |> render_click()
    assert has_element?(lv, "#yandex-eda-client-id", YandexEda.get_settings().client_id)

    lv
    |> form("#yandex-eda-branch",
      yandex_eda: %{enabled: "true", accept_mode: "manual", markup_percent: "15"}
    )
    |> render_submit()

    assert %{enabled: true, accept_mode: :manual, markup_percent: 15} =
             YandexEda.get_branch_settings(branch.id)
  end

  test "products are switched off for the channel", %{conn: conn} do
    branch = yandex_branch()
    product = menu_product(branch, menu_category(branch))

    {:ok, lv, _html} =
      live(
        sign_in(conn, branch, ["branches.read", "products.update"]),
        ~p"/staff/integrations/yandex-eda"
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
      live(sign_in(conn, branch, ["branches.read"]), ~p"/staff/integrations/yandex-eda")

    assert has_element?(lv, "#yandex_eda_enabled[disabled]")
  end
end
