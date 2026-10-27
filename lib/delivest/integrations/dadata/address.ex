defmodule Delivest.Integrations.Dadata.Address do
  @type t :: %{
          value: String.t(),
          city: String.t() | nil,
          street: String.t() | nil,
          house: String.t() | nil,
          latitude: float() | nil,
          longitude: float() | nil,
          fias_id: String.t() | nil,
          postal_code: String.t() | nil,
          district: String.t() | nil,
          geo_precision: integer() | nil
        }

  @spec from_suggestion(map()) :: t()
  def from_suggestion(%{"value" => value, "data" => data}) do
    %{
      value: value,
      city: data["city"] || data["settlement"],
      street: data["street_with_type"] || data["settlement_with_type"],
      house: house(data),
      latitude: coordinate(data["geo_lat"]),
      longitude: coordinate(data["geo_lon"]),
      fias_id: data["house_fias_id"] || data["fias_id"],
      postal_code: data["postal_code"],
      district: data["city_district_with_type"],
      geo_precision: precision(data["qc_geo"])
    }
  end

  defp precision(value) when is_integer(value), do: value

  defp precision(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, _rest} -> number
      :error -> nil
    end
  end

  defp precision(_value), do: nil

  defp house(data) do
    [data["house"], data["block_type"], data["block"]]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> case do
      [] -> nil
      parts -> Enum.join(parts, " ")
    end
  end

  defp coordinate(nil), do: nil
  defp coordinate(value) when is_number(value), do: value / 1

  defp coordinate(value) when is_binary(value) do
    case Float.parse(value) do
      {number, _rest} -> number
      :error -> nil
    end
  end
end
