defmodule Delivest.Integrations.YandexEda.Schedule do
  @days ~w(monday tuesday wednesday thursday friday saturday sunday)
  @keys ~w(mon tue wed thu fri sat sun)

  def build(working_hours) do
    working_hours = working_hours || %{}

    @days
    |> Enum.map(&intervals(Map.get(working_hours, &1)))
    |> spill_over_midnight()
    |> Enum.zip(@keys)
    |> Map.new(fn {intervals, key} -> {key, intervals} end)
  end

  defp intervals(%{"open" => open, "close" => close} = day)
       when is_binary(open) and is_binary(close) do
    cond do
      not enabled?(day["enabled"]) -> {[], nil}
      close > open -> {[interval(open, close)], nil}
      close == "00:00" -> {[interval(open, "24:00")], nil}
      true -> {[interval(open, "24:00")], interval("00:00", close)}
    end
  end

  defp intervals(_day), do: {[], nil}

  defp spill_over_midnight(days) do
    previous = [List.last(days) | Enum.drop(days, -1)]

    Enum.zip_with(days, previous, fn {own, _spill}, {_own, spill} ->
      if spill, do: [spill | own], else: own
    end)
  end

  defp enabled?(value), do: value in [true, "true"]

  defp interval(start, finish), do: %{start: start, end: finish}
end
