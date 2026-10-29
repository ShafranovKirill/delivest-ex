defmodule Delivest.Integrations.YandexEda.Zones do
  alias Delivest.{Delivery, Money}
  alias Delivest.Delivery.{Geometry, Threshold, Zone}
  alias Delivest.Integrations.YandexEda.Schedule

  @fallback_minutes 60

  def list(branch) do
    if zones_mode?(branch.id) do
      for zone <- Delivery.list_zones(branch.id), zone.enabled do
        %{
          name: zone.name,
          coordinates:
            Enum.map(Geometry.ring(zone.polygon), fn [lng, lat] -> %{lt: lat, lg: lng} end),
          meta: meta(zone, branch, zone.geometry_version, true)
        }
      end
    else
      []
    end
  end

  def metas(branch) do
    active? = zones_mode?(branch.id)

    for zone <- Delivery.list_all_zones(branch.id),
        version <- 1..zone.geometry_version do
      current? = version == zone.geometry_version and is_nil(zone.deleted_at)
      meta(zone, branch, version, active? and current? and zone.enabled)
    end
  end

  def zone_id(%Zone{id: id}, version), do: "#{id}-v#{version}"

  defp meta(zone, branch, version, enabled) do
    %{
      zoneId: zone_id(zone, version),
      enabled: enabled,
      intervals: Schedule.build(branch.info.working_hours),
      averageDeliveryTime: minutes(zone, branch),
      thresholds: thresholds(zone.thresholds)
    }
  end

  defp zones_mode?(branch_id), do: Delivery.get_settings(branch_id).mode == :zones

  defp minutes(%Zone{delivery_minutes: minutes}, _branch) when is_integer(minutes), do: minutes
  defp minutes(_zone, %{info: %{delivery_time: minutes}}) when is_integer(minutes), do: minutes
  defp minutes(_zone, _branch), do: @fallback_minutes

  defp thresholds([]), do: [threshold(0, 0)]

  defp thresholds(thresholds) do
    for %Threshold{order_from: from, price: price} <- Threshold.sort(thresholds),
        do: threshold(from, price)
  end

  defp threshold(order_from, price),
    do: %{orderCost: money(order_from), deliveryCost: money(price)}

  defp money(value), do: %{currency: "RUB", value: Money.to_rubles(value)}
end
