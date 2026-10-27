defmodule Delivest.DeliveryTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Delivery

  @square %{
    "type" => "Polygon",
    "coordinates" => [[[37.0, 55.0], [38.0, 55.0], [38.0, 56.0], [37.0, 56.0], [37.0, 55.0]]]
  }

  @inside {55.5, 37.5}
  @outside {54.0, 37.5}

  setup do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    %{branch: branch, staff: staff}
  end

  defp thresholds(pairs),
    do: for({from, price} <- pairs, do: %{"order_from" => from, "price" => price})

  describe "flat delivery" do
    test "is free without conditions", %{branch: branch} do
      assert {:ok, %{price: 0, min_order: 0, zone: nil}} = Delivery.quote(branch.id, nil, 100)
    end

    test "costs a fixed price and becomes free from a sum", %{branch: branch, staff: staff} do
      {:ok, _} =
        Delivery.update_settings(staff, branch.id, %{
          "mode" => "flat",
          "thresholds" => thresholds([{0, 200}, {1500, 0}])
        })

      assert {:ok, %{price: 200, free_from: 1500}} = Delivery.quote(branch.id, nil, 900)
      assert {:ok, %{price: 0, free_from: nil}} = Delivery.quote(branch.id, nil, 1500)
    end

    test "below the minimum is refused", %{branch: branch, staff: staff} do
      {:ok, _} =
        Delivery.update_settings(staff, branch.id, %{"thresholds" => thresholds([{700, 150}])})

      assert {:error, {:below_minimum, 700}} = Delivery.quote(branch.id, nil, 500)
    end
  end

  describe "zones" do
    setup %{branch: branch, staff: staff} do
      {:ok, _} = Delivery.update_settings(staff, branch.id, %{"mode" => "zones"})
      {:ok, zone} = Delivery.create_zone(staff, branch.id, @square)

      {:ok, zone} =
        Delivery.update_zone(staff, branch.id, zone.id, %{
          "thresholds" => thresholds([{500, 300}, {2000, 0}]),
          "delivery_minutes" => 50
        })

      %{zone: zone}
    end

    test "the price comes from the zone of the point", %{branch: branch, zone: zone} do
      assert {:ok, %{zone: found, price: 300, min_order: 500, free_from: 2000, minutes: 50}} =
               Delivery.quote(branch.id, @inside, 800)

      assert found.id == zone.id
    end

    test "points outside the zones and without coordinates are refused", %{branch: branch} do
      assert {:error, :outside_zones} = Delivery.quote(branch.id, @outside, 800)
      assert {:error, :no_coordinates} = Delivery.quote(branch.id, nil, 800)
    end

    test "disabled and deleted zones do not deliver", %{branch: branch, staff: staff, zone: zone} do
      {:ok, _} = Delivery.update_zone(staff, branch.id, zone.id, %{"enabled" => false})
      assert {:error, :outside_zones} = Delivery.quote(branch.id, @inside, 800)

      {:ok, _} = Delivery.update_zone(staff, branch.id, zone.id, %{"enabled" => true})
      {:ok, _} = Delivery.delete_zone(staff, branch.id, zone.id)
      assert {:error, :outside_zones} = Delivery.quote(branch.id, @inside, 800)
      assert [_deleted] = Delivery.list_all_zones(branch.id)
    end

    test "the first zone by position wins", %{branch: branch, staff: staff, zone: zone} do
      {:ok, inner} = Delivery.create_zone(staff, branch.id, @square)
      {:ok, _} = Delivery.update_zone(staff, branch.id, inner.id, %{"position" => -1})

      assert {:ok, %{zone: found, price: 0}} = Delivery.quote(branch.id, @inside, 800)
      assert found.id == inner.id
      refute found.id == zone.id
    end

    test "a new shape bumps the geometry version", %{branch: branch, staff: staff, zone: zone} do
      {:ok, same} = Delivery.update_zone_polygon(staff, branch.id, zone.id, @square)
      assert same.geometry_version == 1

      moved = put_in(@square, ["coordinates"], [[[37.0, 55.0], [39.0, 55.0], [38.0, 56.0]]])
      {:ok, changed} = Delivery.update_zone_polygon(staff, branch.id, zone.id, moved)
      assert changed.geometry_version == 2
      assert length(hd(changed.polygon["coordinates"])) == 4
    end

    test "broken shapes are refused", %{branch: branch, staff: staff} do
      line = %{"type" => "Polygon", "coordinates" => [[[37.0, 55.0], [38.0, 55.0]]]}
      assert {:error, changeset} = Delivery.create_zone(staff, branch.id, line)
      assert %{polygon: [_]} = errors_on(changeset)
      assert {:error, _} = Delivery.create_zone(staff, branch.id, %{"type" => "Point"})
    end
  end

  test "only branch editors change delivery", %{branch: branch} do
    staff = insert(:staff)
    assert {:error, :forbidden} = Delivery.update_settings(staff, branch.id, %{"mode" => "zones"})
    assert {:error, :forbidden} = Delivery.create_zone(staff, branch.id, @square)
  end

  test "repeated order sums are refused", %{branch: branch, staff: staff} do
    assert {:error, changeset} =
             Delivery.update_settings(staff, branch.id, %{
               "thresholds" => thresholds([{0, 200}, {0, 100}])
             })

    assert %{thresholds: [_]} = errors_on(changeset)
  end
end
