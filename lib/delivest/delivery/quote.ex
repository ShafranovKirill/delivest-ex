defmodule Delivest.Delivery.Quote do
  alias Delivest.Delivery.{Geometry, Settings, Threshold, Zone}

  @type t :: %{
          zone: Zone.t() | nil,
          price: non_neg_integer(),
          min_order: non_neg_integer(),
          free_from: non_neg_integer() | nil,
          minutes: pos_integer() | nil
        }

  def find_zone(zones, {_lat, _lng} = point) do
    zones
    |> Enum.filter(& &1.enabled)
    |> Enum.sort_by(& &1.position)
    |> Enum.find(&Geometry.contains?(&1.polygon, point))
  end

  def run(%Settings{mode: :flat, thresholds: thresholds}, _zones, _point, subtotal),
    do: price(thresholds, subtotal, nil, nil)

  def run(%Settings{mode: :zones}, _zones, nil, _subtotal), do: {:error, :no_coordinates}

  def run(%Settings{mode: :zones} = settings, zones, point, subtotal) do
    case find_zone(zones, point) do
      nil when settings.outside_zones -> price(settings.thresholds, subtotal, nil, nil)
      nil -> {:error, :outside_zones}
      zone -> price(zone.thresholds, subtotal, zone, zone.delivery_minutes)
    end
  end

  defp price([], _subtotal, zone, minutes),
    do: {:ok, %{zone: zone, price: 0, min_order: 0, free_from: nil, minutes: minutes}}

  defp price(thresholds, subtotal, zone, minutes) do
    sorted = Threshold.sort(thresholds)
    min_order = hd(sorted).order_from

    case sorted |> Enum.filter(&(&1.order_from <= subtotal)) |> List.last() do
      nil ->
        {:error, {:below_minimum, min_order}}

      threshold ->
        {:ok,
         %{
           zone: zone,
           price: threshold.price,
           min_order: min_order,
           free_from: free_from(sorted, threshold),
           minutes: minutes
         }}
    end
  end

  defp free_from(_sorted, %Threshold{price: 0}), do: nil

  defp free_from(sorted, current) do
    Enum.find_value(sorted, fn threshold ->
      if threshold.price == 0 and threshold.order_from > current.order_from,
        do: threshold.order_from
    end)
  end
end
