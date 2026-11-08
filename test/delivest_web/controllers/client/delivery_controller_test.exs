defmodule DelivestWeb.Client.DeliveryControllerTest do
  use DelivestWeb.ConnCase, async: true

  import Delivest.Factory

  alias Delivest.Delivery

  @square %{
    "type" => "Polygon",
    "coordinates" => [[[37.0, 55.0], [38.0, 55.0], [38.0, 56.0], [37.0, 56.0], [37.0, 55.0]]]
  }

  setup do
    branch = insert(:branch, is_active: true)
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))
    %{branch: branch, admin: admin}
  end

  defp fetch_quote(conn, params),
    do: conn |> get(~p"/client/delivery/quote", params) |> json_response(200)

  test "flat delivery is free by default", %{conn: conn, branch: branch} do
    assert %{
             "data" => %{
               "status" => "ok",
               "price" => 0,
               "zone_id" => nil,
               "zone_name" => nil,
               "zone_color" => nil
             }
           } =
             fetch_quote(conn, %{branch_id: branch.id, subtotal: 100})
  end

  test "zones give the price, the minimum and the free sum", %{
    conn: conn,
    branch: branch,
    admin: admin
  } do
    {:ok, _} = Delivery.update_settings(admin, branch.id, %{"mode" => "zones"})
    {:ok, zone} = Delivery.create_zone(admin, branch.id, @square)

    {:ok, _} =
      Delivery.update_zone(admin, branch.id, zone.id, %{
        "delivery_minutes" => 45,
        "thresholds" => [
          %{"order_from" => 500, "price" => 150},
          %{"order_from" => 1500, "price" => 0}
        ]
      })

    inside = %{branch_id: branch.id, latitude: "55.5", longitude: "37.5"}

    assert %{
             "data" => %{
               "status" => "ok",
               "price" => 150,
               "free_from" => 1500,
               "minutes" => 45,
               "zone_id" => zone_id,
               "zone_name" => zone_name,
               "zone_color" => zone_color
             }
           } =
             fetch_quote(conn, Map.put(inside, :subtotal, 800))

    assert {zone_id, zone_name, zone_color} == {zone.id, zone.name, zone.color}

    assert %{"data" => %{"status" => "ok", "price" => 150}} =
             fetch_quote(conn, Map.merge(inside, %{subtotal: 800, city: "Соседний город"}))

    assert %{
             "data" => %{
               "status" => "below_minimum",
               "min_order" => 500,
               "price" => 150,
               "zone_id" => ^zone_id
             }
           } =
             fetch_quote(conn, Map.put(inside, :subtotal, 300))

    assert %{
             "data" => %{
               "status" => "outside_zones",
               "price" => nil,
               "zone_id" => nil,
               "zone_name" => nil,
               "zone_color" => nil
             }
           } =
             fetch_quote(conn, %{
               branch_id: branch.id,
               latitude: "50",
               longitude: "37.5",
               subtotal: 800
             })

    assert %{
             "data" => %{
               "status" => "no_coordinates",
               "zone_id" => nil,
               "zone_name" => nil,
               "zone_color" => nil
             }
           } =
             fetch_quote(conn, %{branch_id: branch.id, subtotal: 800})

    refute Map.has_key?(fetch_quote(conn, Map.put(inside, :subtotal, 800))["data"], "zone")
  end

  test "zones are shown to customers only when allowed", %{
    conn: conn,
    branch: branch,
    admin: admin
  } do
    {:ok, _} = Delivery.update_settings(admin, branch.id, %{"mode" => "zones"})
    {:ok, zone} = Delivery.create_zone(admin, branch.id, @square)

    {:ok, _} =
      Delivery.update_zone(admin, branch.id, zone.id, %{
        "delivery_minutes" => 35,
        "thresholds" => [%{"order_from" => 500, "price" => 150}]
      })

    fetch = fn ->
      conn |> get(~p"/client/delivery/zones", %{branch_id: branch.id}) |> json_response(200)
    end

    assert %{"data" => []} = fetch.()

    {:ok, _} = Delivery.update_settings(admin, branch.id, %{"show_zones" => true})

    assert %{
             "data" => [
               %{"id" => id, "color" => _, "name" => _, "polygon" => %{"type" => "Polygon"}} =
                 shown
             ]
           } =
             fetch.()

    assert id == zone.id
    assert shown["thresholds"] == [%{"order_from" => 500, "price" => 150}]
    assert shown["delivery_minutes"] == 35
  end

  test "overlap quotes expose only the winning zone", %{conn: conn, branch: branch, admin: admin} do
    {:ok, _} = Delivery.update_settings(admin, branch.id, %{"mode" => "zones"})
    {:ok, outer} = Delivery.create_zone(admin, branch.id, @square)

    {:ok, _} =
      Delivery.update_zone(admin, branch.id, outer.id, %{
        "thresholds" => [%{"order_from" => 0, "price" => 300}]
      })

    {:ok, inner} = Delivery.create_zone(admin, branch.id, @square)

    {:ok, _} =
      Delivery.update_zone(admin, branch.id, inner.id, %{
        "thresholds" => [%{"order_from" => 1000, "price" => 100}]
      })

    point = %{branch_id: branch.id, latitude: "55.5", longitude: "37.5"}

    assert %{"data" => %{"status" => "below_minimum", "zone_id" => id, "min_order" => 1000}} =
             fetch_quote(conn, Map.put(point, :subtotal, 500))

    assert id == inner.id

    assert %{"data" => %{"status" => "ok", "zone_id" => ^id, "price" => 100}} =
             fetch_quote(conn, Map.put(point, :subtotal, 1500))
  end

  test "an unknown branch is 404", %{conn: conn} do
    assert %{"error" => "branch_not_found"} =
             conn |> get(~p"/client/delivery/quote", %{branch_id: "nope"}) |> json_response(404)
  end
end
