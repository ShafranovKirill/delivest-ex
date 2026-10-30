defmodule Delivest.Integrations.AtolOnline.Kkt do
  @fn_full_percent 90
  @fn_expiring_days 30
  @unsent_seconds 3600

  def issues(registers, now \\ DateTime.utc_now()) do
    registers
    |> Enum.flat_map(&register_issues(&1, now))
    |> Enum.uniq()
  end

  defp register_issues(data, now) do
    [
      offline(data, now),
      fn_full(data),
      fn_expiring(data, now)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp offline(%{"networkErrorCode" => code}, _now) when is_integer(code) and code > 0,
    do: :offline

  defp offline(%{"unsentDocs" => docs, "firstUnsetDocTimestamp" => first}, now)
       when is_integer(docs) and docs > 0 do
    case DateTime.from_iso8601(first) do
      {:ok, at, _offset} -> if DateTime.diff(now, at) > @unsent_seconds, do: :offline
      _error -> nil
    end
  end

  defp offline(_data, _now), do: nil

  defp fn_full(%{"fiscalStoragePercentageUse" => percent})
       when is_number(percent) and percent > @fn_full_percent,
       do: :fn_full

  defp fn_full(_data), do: nil

  defp fn_expiring(%{"fiscalStorageExpiration" => expiration}, now) when is_binary(expiration) do
    case DateTime.from_iso8601(expiration) do
      {:ok, at, _offset} ->
        if DateTime.diff(at, now) < @fn_expiring_days * 86_400, do: :fn_expiring

      _error ->
        nil
    end
  end

  defp fn_expiring(_data, _now), do: nil
end
