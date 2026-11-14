defmodule DelivestWeb.Staff.OrderLive.OrdersQuery do
  alias Delivest.LocalTime

  @keys [
    "search",
    "period",
    "status",
    "receiving",
    "payment",
    "source",
    "problem",
    "sort",
    "date_from",
    "date_to",
    "page",
    "page_size"
  ]
  @page_size 25

  def parse(params, branch_id) do
    selected = %{
      search: scalar(params, "search", ""),
      period: scalar(params, "period", "today"),
      status: scalar(params, "status", ""),
      receiving: scalar(params, "receiving", ""),
      payment: scalar(params, "payment", ""),
      source: scalar(params, "source", ""),
      problem: Map.get(params, "problem", "") == "true",
      sort: scalar(params, "sort", "urgency"),
      date_from: scalar(params, "date_from", ""),
      date_to: scalar(params, "date_to", "")
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
        receiving: selected.receiving,
        payment: selected.payment,
        source: selected.source,
        problem: selected.problem,
        sort: selected.sort,
        date_from: date_from,
        date_to: date_to
      },
      page: %{
        page: page_param(params["page"], 1),
        page_size: page_param(params["page_size"], @page_size)
      },
      query: clean(params)
    }
  end

  def clean(params) do
    params
    |> Map.take(@keys)
    |> Map.reject(fn {key, value} ->
      (not is_binary(value) and not (key in ["page", "page_size"] and is_integer(value))) or
        value in [nil, ""] or (key == "problem" and value == "false")
    end)
  end

  defp scalar(params, key, fallback) do
    case params[key] do
      value when is_binary(value) -> value
      _ -> fallback
    end
  end

  defp page_param(value, _fallback) when is_integer(value) and value > 0, do: value

  defp page_param(value, fallback) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> number
      _ -> fallback
    end
  end

  defp page_param(_value, fallback), do: fallback

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
