defmodule DelivestWeb.Client.Delivery.DeliveryJSON do
  def quote(%{quote: quote}), do: %{data: quote}

  def zones(%{zones: zones}),
    do: %{data: Enum.map(zones, &Map.take(&1, [:id, :name, :color, :polygon]))}
end
