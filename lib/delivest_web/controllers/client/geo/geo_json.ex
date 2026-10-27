defmodule DelivestWeb.Client.Geo.GeoJSON do
  def index(%{addresses: addresses}), do: %{data: addresses}
end
