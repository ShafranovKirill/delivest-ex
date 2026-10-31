defmodule DelivestWeb.Staff.DeliveryLive.ZonesTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Delivery
  alias Delivest.Identity.Branch.BranchInfo

  @square %{
    "type" => "Polygon",
    "coordinates" => [[[37.0, 55.0], [38.0, 55.0], [38.0, 56.0], [37.0, 56.0], [37.0, 55.0]]]
  }

  defp sign_in(conn, branch, permissions) do
    staff = insert(:staff, role: insert(:role, permissions: permissions))
    insert(:staff_branch, staff: staff, branch: branch)
    init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
  end

  test "flat delivery is saved from the three fields", %{conn: conn} do
    branch = insert(:branch)

    {:ok, lv, _html} =
      live(
        sign_in(conn, branch, ["delivery.read", "delivery.update"]),
        ~p"/staff/b/#{branch}/delivery/zones"
      )

    lv
    |> form("#delivery-settings",
      delivery: %{mode: "flat", min_order: "", price: "200", free_from: "1500"}
    )
    |> render_submit()

    assert %{mode: :flat, thresholds: thresholds} = Delivery.get_settings(branch.id)
    assert Enum.map(thresholds, &{&1.order_from, &1.price}) == [{0, 20_000}, {150_000, 0}]
  end

  test "zones are drawn, edited and deleted", %{conn: conn} do
    branch = insert(:branch)

    {:ok, lv, _html} =
      live(
        sign_in(conn, branch, ["delivery.read", "delivery.update"]),
        ~p"/staff/b/#{branch}/delivery/zones"
      )

    lv |> form("#delivery-settings", delivery: %{mode: "zones"}) |> render_change()
    assert has_element?(lv, "#delivery-zone-map")

    lv |> form("#delivery-settings", delivery: %{mode: "zones"}) |> render_submit()
    assert %{mode: :zones} = Delivery.get_settings(branch.id)

    render_hook(lv, "zone_drawn", %{"polygon" => @square})
    assert [zone] = Delivery.list_zones(branch.id)
    assert_push_event(lv, "zones:reset", %{selected: selected})
    assert selected == zone.id

    lv
    |> form("#delivery-zone-form",
      zone: %{
        name: "Центр",
        price: "150",
        min_order: "500",
        free_from: "",
        delivery_minutes: "40"
      }
    )
    |> render_submit()

    assert [
             %{
               name: "Центр",
               delivery_minutes: 40,
               thresholds: [%{order_from: 50_000, price: 15_000}]
             }
           ] =
             Delivery.list_zones(branch.id)

    assert has_element?(lv, "#delivery-zone-#{zone.id}", "150 ₽")

    moved =
      put_in(@square, ["coordinates"], [[[37.0, 55.0], [39.0, 55.0], [38.0, 56.0], [37.0, 55.0]]])

    render_hook(lv, "zone_shape", %{"id" => zone.id, "polygon" => moved})
    assert [%{geometry_version: 2}] = Delivery.list_zones(branch.id)

    lv |> element("#delivery-zone-form button[phx-click=delete_zone]") |> render_click()
    assert [] = Delivery.list_zones(branch.id)
  end

  test "zones are shown to customers, deliver outside and grow by radius", %{conn: conn} do
    branch = insert(:branch)
    Delivest.Repo.insert!(%BranchInfo{branch_id: branch.id, latitude: 52.97, longitude: 36.06})
    Cachex.clear(:branch_cache)

    {:ok, lv, _html} =
      live(
        sign_in(conn, branch, ["delivery.read", "delivery.update"]),
        ~p"/staff/b/#{branch}/delivery/zones"
      )

    lv |> form("#delivery-settings", delivery: %{mode: "zones"}) |> render_change()
    refute has_element?(lv, "#delivery-settings input[name='delivery[price]']")

    lv
    |> form("#delivery-settings", delivery: %{mode: "zones", outside_zones: "true"})
    |> render_change()

    lv
    |> form("#delivery-settings",
      delivery: %{mode: "zones", show_zones: "true", outside_zones: "true", price: "300"}
    )
    |> render_submit()

    assert %{mode: :zones, show_zones: true, outside_zones: true, thresholds: [%{price: 30_000}]} =
             Delivery.get_settings(branch.id)

    lv |> form("#delivery-radius-zone", %{radius: "5"}) |> render_submit()
    assert [%{radius_km: 5.0} = zone] = Delivery.list_zones(branch.id)

    lv |> form("#delivery-zone-form", zone: %{radius_km: "8"}) |> render_submit()
    assert [%{id: id, radius_km: 8.0}] = Delivery.list_zones(branch.id)
    assert id == zone.id
  end

  test "staff without branch editing only looks", %{conn: conn} do
    branch = insert(:branch)

    {:ok, _} =
      Delivery.update_settings(
        insert(:staff, role: insert(:role, permissions: ["admin"])),
        branch.id,
        %{"mode" => "zones"}
      )

    {:ok, lv, _html} =
      live(sign_in(conn, branch, ["delivery.read"]), ~p"/staff/b/#{branch}/delivery/zones")

    refute has_element?(lv, "#delivery-draw-zone")
    render_hook(lv, "zone_drawn", %{"polygon" => @square})
    assert [] = Delivery.list_zones(branch.id)
  end
end
