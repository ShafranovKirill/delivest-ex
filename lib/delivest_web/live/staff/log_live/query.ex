defmodule DelivestWeb.Staff.LogLive.Query do
  use DelivestWeb, :verified_routes

  @keys ~w(type level q page page_size)
  @page_size 50

  def filters(params) do
    params
    |> Map.take(@keys)
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  def flop(scope, filters) do
    %{
      "page" => Map.get(filters, "page", 1),
      "page_size" => Map.get(filters, "page_size", @page_size),
      "filters" => conditions(scope, filters)
    }
  end

  def path(scope, filters), do: base(scope) <> query(filters)

  defp conditions(:events, filters), do: condition([], "subject_type", :==, filters["type"])

  defp conditions(_scope, filters) do
    []
    |> condition("level", :==, filters["level"])
    |> condition("message", :ilike, filters["q"])
  end

  defp condition(acc, _field, _op, nil), do: acc

  defp condition(acc, field, op, value),
    do: acc ++ [%{"field" => field, "op" => op, "value" => value}]

  defp base(:events), do: ~p"/staff/logs"
  defp base(:raw), do: ~p"/staff/logs/raw"
  defp base(:errors), do: ~p"/staff/logs/errors"
  defp base(:hints), do: ~p"/staff/logs/hints"

  defp query(filters) when map_size(filters) == 0, do: ""
  defp query(filters), do: "?" <> URI.encode_query(filters)
end
