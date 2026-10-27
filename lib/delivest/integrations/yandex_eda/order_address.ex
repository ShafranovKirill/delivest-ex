defmodule Delivest.Integrations.YandexEda.OrderAddress do
  alias Delivest.Integrations.Dadata

  @located [:city, :street, :house, :fias_id, :postal_code, :district, :geo_precision]

  def build(nil), do: nil

  def build(%{full: full, latitude: latitude, longitude: longitude}) do
    %{"formatted" => String.slice(full, 0, 255), "latitude" => latitude, "longitude" => longitude}
    |> Map.merge(locate(latitude, longitude))
  end

  defp locate(latitude, longitude) do
    case Dadata.geolocate(latitude, longitude) do
      {:ok, [address | _]} ->
        for field <- @located,
            value = Map.get(address, field),
            into: %{},
            do: {to_string(field), value}

      _ ->
        %{}
    end
  end
end
