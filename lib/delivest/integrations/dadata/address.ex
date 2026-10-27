defmodule Delivest.Integrations.Dadata.Address do
  @type t :: %{
          value: String.t(),
          city: String.t() | nil,
          street: String.t() | nil,
          house: String.t() | nil,
          latitude: float() | nil,
          longitude: float() | nil
        }

  @spec from_suggestion(map()) :: t()
  def from_suggestion(%{"value" => value, "data" => data}) do
    %{
      value: value,
      city: data["city"] || data["settlement"],
      street: data["street_with_type"] || data["settlement_with_type"],
      house: house(data),
      latitude: coordinate(data["geo_lat"]),
      longitude: coordinate(data["geo_lon"])
    }
  end

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
