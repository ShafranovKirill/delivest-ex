defmodule DelivestWeb.Staff.Foundation.ListState do
  @moduledoc """
  URL backed state for staff lists. Callers must fetch a page on the server using
  `query/1`; selection is restricted to the IDs in that fetched page.
  """

  @per_page [25, 50, 100]
  defstruct query: "",
            filters: %{},
            sort: "name",
            direction: "asc",
            page: 1,
            per_page: 25,
            scope: "all",
            selected: MapSet.new()

  def from_params(params, opts \\ []) do
    allowed_sorts = Keyword.get(opts, :sorts, ["name"])
    allowed_filters = Keyword.get(opts, :filters, [])
    scope = Keyword.get(opts, :scope, "all")

    %__MODULE__{
      query: if(is_binary(params["q"]), do: String.trim(params["q"]), else: ""),
      filters:
        Map.take(params, allowed_filters)
        |> Map.filter(fn {_key, value} -> is_binary(value) and value != "" end),
      sort: if(params["sort"] in allowed_sorts, do: params["sort"], else: hd(allowed_sorts)),
      direction: if(params["direction"] == "desc", do: "desc", else: "asc"),
      page: positive_integer(params["page"], 1),
      per_page: allowed_per_page(params["per_page"]),
      scope: scope
    }
  end

  def query(%__MODULE__{} = state) do
    %{
      q: state.query,
      filters: state.filters,
      sort: state.sort,
      direction: state.direction,
      page: state.page,
      per_page: state.per_page,
      scope: state.scope
    }
  end

  def params(%__MODULE__{} = state) do
    Map.merge(state.filters, %{
      "q" => state.query,
      "sort" => state.sort,
      "direction" => state.direction,
      "page" => state.page,
      "per_page" => state.per_page,
      "scope" => state.scope
    })
  end

  def change(%__MODULE__{} = state, changes) when is_map(changes) do
    state = struct!(state, changes)

    if Enum.any?(
         [:query, :filters, :sort, :direction, :scope, :per_page],
         &Map.has_key?(changes, &1)
       ),
       do: %{state | page: 1, selected: MapSet.new()},
       else: %{state | selected: MapSet.new()}
  end

  def select(%__MODULE__{} = state, ids, page_ids) do
    visible = MapSet.new(page_ids)
    %{state | selected: MapSet.intersection(MapSet.new(ids), visible)}
  end

  def selected_count(%__MODULE__{selected: selected}), do: MapSet.size(selected)

  def empty_kind(0, %__MODULE__{query: "", filters: filters}) when map_size(filters) == 0,
    do: :empty

  def empty_kind(0, _state), do: :no_results
  def empty_kind(_, _state), do: :none

  defp allowed_per_page(value) do
    parsed = positive_integer(value, 25)
    if parsed in @per_page, do: parsed, else: 25
  end

  defp positive_integer(value, fallback) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> number
      _ -> fallback
    end
  end

  defp positive_integer(value, _fallback) when is_integer(value) and value > 0, do: value
  defp positive_integer(_, fallback), do: fallback
end
