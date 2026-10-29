defmodule Delivest.Geo.House do
  @pattern ~r/^(?<house>.+?)(?:\s*(?:корпус|корп\.?|к\.?)\s*(?<block>\d[^\s,]*))?(?:\s*,?\s*(?:строение|стр\.?)\s*(?<building>[^\s,]+))?$/iu

  @spec split(String.t() | nil) :: %{
          house: String.t() | nil,
          block: String.t() | nil,
          building: String.t() | nil
        }
  def split(value) when is_binary(value) do
    case Regex.named_captures(@pattern, String.trim(value)) do
      %{"house" => house} = parts ->
        %{house: blank(house), block: blank(parts["block"]), building: blank(parts["building"])}

      nil ->
        %{house: blank(value), block: nil, building: nil}
    end
  end

  def split(_value), do: %{house: nil, block: nil, building: nil}

  @spec line(map() | nil) :: String.t() | nil
  def line(%{house: house} = address) do
    [
      house,
      prefixed("к", Map.get(address, :block)),
      prefixed("стр", Map.get(address, :building))
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      parts -> Enum.join(parts, " ")
    end
  end

  def line(_address), do: nil

  defp prefixed(_prefix, value) when value in [nil, ""], do: nil
  defp prefixed(prefix, value), do: "#{prefix} #{value}"

  defp blank(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp blank(_value), do: nil
end
