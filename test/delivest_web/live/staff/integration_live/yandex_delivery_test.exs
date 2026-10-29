defmodule DelivestWeb.Staff.IntegrationLive.YandexDeliveryTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Couriers.Delivery
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.YandexDelivery
  alias Delivest.Repo

  setup %{conn: conn} do
    branch = insert(:branch)
    Repo.insert!(%BranchInfo{branch_id: branch.id, couriers: %{source: :yandex, search: :manual}})

    staff =
      insert(:staff,
        role:
          insert(:role,
            permissions: [
              "integrations.read",
              "integrations.update",
              "orders.read",
              "orders.update"
            ]
          )
      )

    insert(:staff_branch, staff: staff, branch: branch)

    %{conn: init_test_session(conn, %{"staff_id" => staff.id}), branch: branch}
  end

  test "saves the settings and keeps the token", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/integrations")
    assert lv |> element("#integration-yandex-delivery") |> render() =~ "Not connected"

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/integrations/yandex-delivery")

    lv
    |> form("#yandex-delivery-settings",
      yandex_delivery: %{
        token: " y-token ",
        contact_email: "kitchen@example.com",
        taxi_class: "express"
      }
    )
    |> render_submit()

    assert %{token: "y-token", taxi_class: :express} = YandexDelivery.settings(branch.id)

    lv
    |> form("#yandex-delivery-settings", yandex_delivery: %{token: "", contact_name: "Кухня"})
    |> render_submit()

    assert %{token: "y-token", contact_name: "Кухня"} = YandexDelivery.settings(branch.id)
    refute render(lv) =~ "y-token"

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/integrations")
    assert lv |> element("#integration-yandex-delivery") |> render() =~ "Calls couriers"
  end

  test "the order card shows the yandex courier", %{conn: conn, branch: branch} do
    order =
      branch.id
      |> order_fixture()
      |> Ecto.Changeset.change(fulfillment_type: :delivery, status: :ready)
      |> Repo.update!()

    order.id
    |> Delivery.new(branch.id, :yandex)
    |> Ecto.Changeset.change(
      status: :assigned,
      external_id: "claim-1",
      details: %{
        "status" => "returning",
        "performer" => %{"name" => "Иван", "car" => "Kia Rio"},
        "phone" => "+79000000001,,0163",
        "tracking_url" => "https://track.example/1"
      }
    )
    |> Repo.insert!()

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/orders")

    panel = lv |> element("#order-delivery-panel-#{order.id}") |> render()
    assert panel =~ "Иван"
    assert panel =~ "Kia Rio"
    assert panel =~ "tel:+79000000001,,0163"
    assert panel =~ "https://track.example/1"
    assert has_element?(lv, "#order-yandex-returning-#{order.id}")
  end

  test "the request journal shows the branch requests and filters errors",
       %{conn: conn, branch: branch} do
    journal = Delivest.Integrations.Journal

    for {status, url} <- [{200, "/claims/info"}, {500, "/claims/create"}] do
      journal.record(%{
        provider: :yandex_delivery,
        branch_id: branch.id,
        direction: :out,
        method: :post,
        url: url,
        status: status,
        response: %{"code" => "x"}
      })
    end

    journal.record(%{
      provider: :yandex_delivery,
      branch_id: Ecto.UUID.generate(),
      direction: :out,
      method: :post,
      url: "/other-branch",
      status: 200
    })

    {:ok, lv, html} = live(conn, ~p"/staff/b/#{branch}/integrations/yandex-delivery")
    assert html =~ "/claims/info"
    assert html =~ "/claims/create"
    refute html =~ "/other-branch"

    html = lv |> element("#yandex-delivery-journal input[type=checkbox]") |> render_click()
    refute html =~ "/claims/info"
    assert html =~ "/claims/create"
  end
end
