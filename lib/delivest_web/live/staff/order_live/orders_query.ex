defmodule DelivestWeb.Staff.OrderLive.OrdersQuery do
  alias Delivest.LocalTime

  @keys [
    "search",
    "period",
    "status",
    "problem",
    "sort",
    "date_from",
    "date_to",
    "page",
    "page_size"
  ]
  @page_size 20

  def parse(params, branch_id) do
    selected = %{
      search: Map.get(params, "search", ""),
      period: Map.get(params, "period", "today"),
      status: Map.get(params, "status", ""),
      problem: Map.get(params, "problem", "") == "true",
      sort: Map.get(params, "sort", "urgency"),
      date_from: Map.get(params, "date_from", ""),
      date_to: Map.get(params, "date_to", "")
    }

    today = LocalTime.today(LocalTime.timezone(branch_id))

    {date_from, date_to} =
      date_range(selected.period, selected.date_from, selected.date_to, today)

    %{
      selected: selected,
      filters: %{
        branch_id: branch_id,
        search: selected.search,
        status: selected.status,
        problem: selected.problem,
        sort: selected.sort,
        date_from: date_from,
        date_to: date_to
      },
      page: %{
        page: Map.get(params, "page", 1),
        page_size: Map.get(params, "page_size", @page_size)
      },
      query: clean(params)
    }
  end

  def clean(params) do
    params
    |> Map.take(@keys)
    |> Map.reject(fn {key, value} ->
      value in [nil, ""] or (key == "problem" and value == "false")
    end)
  end

  defp date_range("today", _from, _to, today), do: {today, today}
  defp date_range("tomorrow", _from, _to, today), do: day(today, 1)
  defp date_range("yesterday", _from, _to, today), do: day(today, -1)
  defp date_range("week", _from, _to, today), do: {Date.add(today, -7), nil}
  defp date_range("month", _from, _to, today), do: {Date.add(today, -30), nil}
  defp date_range("custom", from, to, _today), do: {parse_date(from), parse_date(to)}
  defp date_range(_period, _from, _to, _today), do: {nil, nil}

  defp day(today, offset) do
    date = Date.add(today, offset)
    {date, date}
  end

  defp parse_date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _error -> nil
    end
  end
end
