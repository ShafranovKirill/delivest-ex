defmodule DelivestWeb.Staff.LogLive.Query do
  use DelivestWeb, :verified_routes

  @keys ~w(type actor action branch sort level q page page_size)
  @page_size 25
  @page_sizes ~w(25 50 100)

  def filters(params) do
    params
    |> Map.take(@keys)
    |> Enum.filter(fn
      {_key, value} when not is_binary(value) or value == "" ->
        false

      {"sort", value} ->
        value in sorts()

      {"level", value} ->
        value in ~w(error warning info)

      {"page_size", value} ->
        value in @page_sizes

      {"page", value} ->
        byte_size(value) <= 9 and match?({number, ""} when number > 0, Integer.parse(value))

      {"actor", value} ->
        match?({:ok, _}, Ecto.UUID.cast(value))

      {"branch", value} ->
        match?({:ok, _}, Ecto.UUID.cast(value))

      {_key, value} ->
        String.length(value) <= 200
    end)
    |> Map.new()
  end

  @sorts %{
    "oldest" => {[:inserted_at], [:asc]},
    "actor" => {[:actor_name, :inserted_at], [:asc_nulls_last, :desc]},
    "action" => {[:action, :inserted_at], [:asc, :desc]},
    "branch" => {[:branch_name, :inserted_at], [:asc_nulls_last, :desc]}
  }

  def sorts, do: Map.keys(@sorts)

  def flop(scope, filters) do
    %{
      "page" => Map.get(filters, "page", 1),
      "page_size" => Map.get(filters, "page_size", @page_size),
      "filters" => conditions(scope, filters)
    }
    |> order(scope, filters["sort"])
  end

  def default_view?(filters), do: Map.take(filters, ~w(actor action branch sort)) == %{}

  defp order(flop, :events, sort) when is_map_key(@sorts, sort) do
    {fields, directions} = Map.fetch!(@sorts, sort)
    Map.merge(flop, %{"order_by" => fields, "order_directions" => directions})
  end

  defp order(flop, _scope, _sort), do: flop

  def path(scope, filters), do: base(scope) <> query(filters)

  defp conditions(:events, filters) do
    []
    |> condition("subject_type", :==, filters["type"])
    |> condition("actor_id", :==, filters["actor"])
    |> condition("action", :==, filters["action"])
    |> condition("branch_id", :==, filters["branch"])
  end

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

  defp query(filters) when map_size(filters) == 0, do: ""
  defp query(filters), do: "?" <> URI.encode_query(filters)
end
