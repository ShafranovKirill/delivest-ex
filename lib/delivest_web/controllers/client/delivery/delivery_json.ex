defmodule DelivestWeb.Client.Delivery.DeliveryJSON do
  def quote(%{quote: quote}), do: %{data: quote}

  def zones(%{zones: zones}) do
    %{
      data:
        Enum.map(zones, fn zone ->
          zone
          |> Map.take([:id, :name, :color, :polygon, :delivery_minutes])
          |> Map.put(:thresholds, Enum.map(zone.thresholds, &Map.take(&1, [:order_from, :price])))
        end)
    }
  end
end
