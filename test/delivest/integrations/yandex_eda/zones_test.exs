defmodule Delivest.Integrations.YandexEda.ZonesTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory
  import Delivest.YandexEdaFixtures

  alias Delivest.Delivery
  alias Delivest.Integrations.YandexEda

  @square %{
    "type" => "Polygon",
    "coordinates" => [[[37.0, 55.0], [38.0, 55.0], [38.0, 56.0], [37.0, 56.0], [37.0, 55.0]]]
  }

  setup do
    branch =
      yandex_branch([],
        delivery_time: 45,
        working_hours: %{"monday" => %{"enabled" => true, "open" => "10:00", "close" => "22:00"}}
      )

    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    {:ok, zone} = Delivery.create_zone(staff, branch.id, @square)
    %{branch: branch, staff: staff, zone: zone}
  end

  defp zones_mode(staff, branch),
    do: {:ok, _} = Delivery.update_settings(staff, branch.id, %{"mode" => "zones"})

  test "flat delivery has no zones", %{branch: branch} do
    assert {:ok, []} = YandexEda.zones(branch.id)
    assert {:ok, [%{enabled: false}]} = YandexEda.zone_metas(branch.id)
  end

  test "zones carry the polygon and the delivery terms", %{
    branch: branch,
    staff: staff,
    zone: zone
  } do
    zones_mode(staff, branch)

    {:ok, _} =
      Delivery.update_zone(staff, branch.id, zone.id, %{
        "thresholds" => [
          %{"order_from" => 2000, "price" => 0},
          %{"order_from" => 500, "price" => 300}
        ]
      })

    zone_id = "#{zone.id}-v1"

    assert {:ok, [%{name: "Зона 1", coordinates: coordinates, meta: meta}]} =
             YandexEda.zones(branch.id)

    assert length(coordinates) == 5
    assert hd(coordinates) == %{lt: 55.0, lg: 37.0}

    assert %{
             zoneId: ^zone_id,
             enabled: true,
             averageDeliveryTime: 45,
             intervals: %{"mon" => [%{start: "10:00", end: "22:00"}], "tue" => []},
             thresholds: [
               %{orderCost: %{currency: "RUB", value: 500}, deliveryCost: %{value: 300}},
               %{orderCost: %{value: 2000}, deliveryCost: %{value: 0}}
             ]
           } = meta
  end

  test "zone minutes win and empty terms deliver for free", %{
    branch: branch,
    staff: staff,
    zone: zone
  } do
    zones_mode(staff, branch)
    {:ok, _} = Delivery.update_zone(staff, branch.id, zone.id, %{"delivery_minutes" => 30})

    assert {:ok, [%{meta: %{averageDeliveryTime: 30, thresholds: [threshold]}}]} =
             YandexEda.zones(branch.id)

    assert threshold == %{
             orderCost: %{currency: "RUB", value: 0},
             deliveryCost: %{currency: "RUB", value: 0}
           }
  end

  test "old shapes and removed zones are switched off", %{
    branch: branch,
    staff: staff,
    zone: zone
  } do
    zones_mode(staff, branch)

    moved =
      update_in(@square, ["coordinates"], fn [ring] ->
        [Enum.map(ring, fn [x, y] -> [x + 1, y] end)]
      end)

    {:ok, _} = Delivery.update_zone_polygon(staff, branch.id, zone.id, moved)
    {:ok, other} = Delivery.create_zone(staff, branch.id, @square)
    {:ok, _} = Delivery.update_zone(staff, branch.id, other.id, %{"enabled" => false})

    assert {:ok, [%{meta: %{zoneId: current}}]} = YandexEda.zones(branch.id)
    assert current == "#{zone.id}-v2"

    {:ok, metas} = YandexEda.zone_metas(branch.id)
    states = Map.new(metas, &{&1.zoneId, &1.enabled})

    assert states == %{
             "#{zone.id}-v1" => false,
             "#{zone.id}-v2" => true,
             "#{other.id}-v1" => false
           }

    {:ok, _} = Delivery.delete_zone(staff, branch.id, zone.id)
    assert {:ok, []} = YandexEda.zones(branch.id)
    assert {:ok, metas} = YandexEda.zone_metas(branch.id)
    refute Enum.any?(metas, & &1.enabled)
  end

  test "unknown restaurants are refused" do
    assert {:error, :restaurant_not_found} = YandexEda.zones(Ecto.UUID.generate())
    assert {:error, :restaurant_not_found} = YandexEda.zone_metas("nope")
  end
end
