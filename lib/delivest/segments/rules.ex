defmodule Delivest.Segments.Rules do
  @moduledoc "Versioned, bounded rule format for dynamic segments. Money is in minor units."

  @metrics ~w(days_since_last_order order_count total_spent avg_check)
  @operators ~w(eq gte lte)
  @max_conditions 8
  @max_money 1_000_000_000_000

  def validate(%{"version" => 1, "match" => match, "conditions" => conditions} = rules)
      when match in ["all", "any"] and is_list(conditions) and
             length(conditions) >= 1 and length(conditions) <= @max_conditions do
    if Map.keys(rules) |> Enum.sort() == ["conditions", "match", "version"] and
         Enum.all?(conditions, &valid_condition?/1) do
      {:ok, rules}
    else
      {:error, :invalid_rules}
    end
  end

  def validate(_), do: {:error, :invalid_rules}

  def match?(rules, metrics, now \\ DateTime.utc_now()) do
    with {:ok, %{"match" => mode, "conditions" => conditions}} <- validate(rules) do
      predicate = fn condition -> match_condition?(condition, metrics, now) end

      if mode == "all",
        do: Enum.all?(conditions, predicate),
        else: Enum.any?(conditions, predicate)
    else
      _ -> false
    end
  end

  defp valid_condition?(%{"metric" => metric, "op" => op, "value" => value} = condition)
       when metric in @metrics and op in @operators and is_integer(value) do
    Map.keys(condition) |> Enum.sort() == ["metric", "op", "value"] and
      value >= 0 and
      value <= if(metric in ~w(total_spent avg_check), do: @max_money, else: 1_000_000)
  end

  defp valid_condition?(_), do: false

  defp match_condition?(%{"metric" => metric, "op" => op, "value" => value}, metrics, now) do
    actual =
      case metric do
        "days_since_last_order" ->
          case metrics.last_order_at do
            nil -> nil
            at -> max(0, div(DateTime.diff(now, at, :second), 86_400))
          end

        "order_count" ->
          metrics.order_count

        "total_spent" ->
          metrics.total_spent

        "avg_check" ->
          div(metrics.total_spent, max(metrics.order_count, 1))
      end

    case {actual, op} do
      {nil, _} -> false
      {number, "eq"} -> number == value
      {number, "gte"} -> number >= value
      {number, "lte"} -> number <= value
    end
  end
end
