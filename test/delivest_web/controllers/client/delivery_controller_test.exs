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
    assert %{"data" => %{"status" => "ok", "price" => 0}} =
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

    assert %{"data" => %{"status" => "ok", "price" => 150, "free_from" => 1500, "minutes" => 45}} =
             fetch_quote(conn, Map.put(inside, :subtotal, 800))

    assert %{"data" => %{"status" => "below_minimum", "min_order" => 500, "price" => 150}} =
             fetch_quote(conn, Map.put(inside, :subtotal, 300))

    assert %{"data" => %{"status" => "outside_zones", "price" => nil}} =
             fetch_quote(conn, %{
               branch_id: branch.id,
               latitude: "50",
               longitude: "37.5",
               subtotal: 800
             })

    assert %{"data" => %{"status" => "no_coordinates"}} =
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
    refute Map.has_key?(shown, "thresholds")
  end

  test "an unknown branch is 404", %{conn: conn} do
    assert %{"error" => "branch_not_found"} =
             conn |> get(~p"/client/delivery/quote", %{branch_id: "nope"}) |> json_response(404)
  end
end
