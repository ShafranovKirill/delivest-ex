defmodule DelivestWeb.Staff.IntegrationLive.YandexDeliveryTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Couriers.Delivery
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.{Health, YandexDelivery}
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

  defp admin, do: insert(:staff, role: build(:role, permissions: ["admin"]))

  test "saves the settings and keeps the token", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/integrations")
    assert lv |> element("#integration-yandex-delivery") |> render() =~ "Not filled in"

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
    assert has_element?(lv, "#yandex-delivery-health-summary-credentials", "Filled in")
    assert has_element?(lv, "#yandex-delivery-health-summary-usage", "On")

    lv
    |> form("#yandex-delivery-settings", yandex_delivery: %{token: "", contact_name: "Кухня"})
    |> render_submit()

    assert %{token: "y-token", contact_name: "Кухня"} = YandexDelivery.settings(branch.id)
    refute render(lv) =~ "y-token"

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/integrations")
    assert lv |> element("#integration-yandex-delivery") |> render() =~ "Automatic courier call"
  end

  test "a saved key change resets the check and the old result never returns",
       %{conn: conn, branch: branch} do
    assert {:ok, _settings} =
             YandexDelivery.update_settings(admin(), branch.id, %{
               "token" => "old-token",
               "contact_email" => "kitchen@example.com"
             })

    assert {:ok, _status} = Health.report(:yandex_delivery, branch.id, YandexDelivery, :ok)

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/integrations/yandex-delivery")
    assert render(lv) =~ "Connection checked"

    lv
    |> form("#yandex-delivery-settings", yandex_delivery: %{token: "new-token"})
    |> render_submit()

    assert render(lv) =~ "Connection not checked"
    assert Health.get(:yandex_delivery, branch.id).checked_at == nil

    lv
    |> form("#yandex-delivery-settings", yandex_delivery: %{token: "draft-token"})
    |> render_change()

    assert render(lv) =~ "Connection not checked"

    Req.Test.stub(Delivest.HTTP.Client, &Req.Test.json(&1, %{}))

    assert lv |> element("#yandex-delivery-health-check") |> render_click() =~
             "Connection checked"
  end

  test "a read-only employee sees the state but cannot run the check",
       %{conn: conn, branch: branch} do
    assert {:ok, _settings} =
             YandexDelivery.update_settings(admin(), branch.id, %{
               "token" => "token",
               "contact_email" => "kitchen@example.com"
             })

    reader = insert(:staff, role: insert(:role, permissions: ["integrations.read"]))
    insert(:staff_branch, staff: reader, branch: branch)

    conn = init_test_session(conn, %{"staff_id" => reader.id})
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/integrations/yandex-delivery")

    refute has_element?(lv, "#yandex-delivery-health-check")

    test_pid = self()

    Req.Test.stub(Delivest.HTTP.Client, fn _conn ->
      send(test_pid, :external_call)
      flunk("the external API must not be called")
    end)

    lv
    |> with_target("#yandex-delivery-health")
    |> render_hook("check")

    refute_received :external_call
    assert Health.get(:yandex_delivery, branch.id) == nil
    assert Delivest.Integrations.Journal.list(:yandex_delivery, branch.id) == []
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
