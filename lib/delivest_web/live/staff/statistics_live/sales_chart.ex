defmodule DelivestWeb.Staff.StatisticsLive.SalesChart do
  use DelivestWeb, :html

  alias DelivestWeb.Staff.OrderLive.OrderHelpers
  import DelivestWeb.Staff.StatsComponents, only: [analytics_chart: 1]

  attr :daily, :list, required: true
  attr :comparison, :map, default: nil
  attr :granularity, :string, required: true
  attr :metric, :atom, required: true
  attr :id, :string, default: nil
  attr :title, :string, default: nil
  attr :compact, :boolean, default: false

  def chart(assigns) do
    current = buckets(assigns.daily, assigns.granularity)

    previous =
      if assigns.comparison, do: buckets(assigns.comparison.daily, assigns.granularity), else: []

    count = max(length(current), length(previous))

    pairs =
      Enum.zip(
        current ++ List.duplicate(nil, count - length(current)),
        previous ++ List.duplicate(nil, count - length(previous))
      )

    chart_id = assigns.id || "statistics-chart-#{assigns.metric}"

    data = %{
      kind: "sales",
      metric: Atom.to_string(assigns.metric),
      title: assigns.title || metric_label(assigns.metric),
      selected: gettext("Selected period"),
      comparison: gettext("Comparison period"),
      labels:
        Enum.map(pairs, fn {selected, comparison} ->
          bucket_label(selected || comparison, assigns.granularity)
        end),
      current: Enum.map(current, &point_data(&1, assigns.metric)),
      previous: Enum.map(previous, &point_data(&1, assigns.metric)),
      locale: Gettext.get_locale(DelivestWeb.Gettext)
    }

    assigns =
      assign(assigns,
        current: current,
        previous: previous,
        pairs: pairs,
        data: data,
        chart_id: chart_id
      )

    ~H"""
    <section
      id={@chart_id}
      class={[
        "min-w-0",
        if(@compact, do: "", else: "rounded-box border border-base-300 bg-base-100 p-4")
      ]}
    >
      <h2 class="font-semibold">{@title || metric_label(@metric)}</h2>
      <p class="mt-1 text-xs text-base-content/60">
        {gettext("Selected period")}: {range_label(@current)}
        <span :if={@comparison}>
          · {gettext("Comparison period")}: {range_label(@previous)}
        </span>
      </p>
      <.analytics_chart
        id={@chart_id <> "-plot"}
        data={@data}
        label={@title || metric_label(@metric)}
        height="h-80"
      >
        <details class="mt-2 text-xs">
          <summary class="cursor-pointer">{gettext("Chart data")}</summary>
          <div class="max-h-64 overflow-auto">
            <table class="table table-xs w-full">
              <thead>
                <tr>
                  <th>{gettext("Selected period")}</th><th :if={@comparison}>
                    {gettext("Comparison period")}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr :for={{current, previous} <- @pairs}>
                  <td
                    data-series={if(current, do: "selected")}
                    data-value={if(current, do: metric_value(current, @metric))}
                  >
                    {if(current, do: point_title(current, @metric), else: "—")}
                  </td>
                  <td :if={@comparison} data-series={if(previous, do: "comparison")}>
                    {if(previous, do: point_title(previous, @metric), else: "—")}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </details>
      </.analytics_chart>
    </section>
    """
  end

  @doc false
  def buckets(rows, granularity) when granularity in ["week", "month"] do
    rows
    |> Enum.group_by(fn row ->
      if(granularity == "week",
        do: Date.beginning_of_week(row.date, :monday),
        else: Date.beginning_of_month(row.date)
      )
    end)
    |> Enum.sort_by(fn {start, _} -> start end, Date)
    |> Enum.map(fn {_start, unsorted_days} ->
      days = Enum.sort_by(unsorted_days, & &1.date, Date)
      revenue = Enum.sum(Enum.map(days, & &1.revenue))
      orders = Enum.sum(Enum.map(days, & &1.orders))

      %{
        from: hd(days).date,
        to: List.last(days).date,
        revenue: revenue,
        orders: orders,
        avg_check: if(orders > 0, do: round(revenue / orders), else: 0)
      }
    end)
  end

  def buckets(rows, _granularity) do
    Enum.map(rows, fn row ->
      %{
        from: row.date,
        to: row.date,
        revenue: row.revenue,
        orders: row.orders,
        avg_check: if(row.orders > 0, do: round(row.revenue / row.orders), else: 0)
      }
    end)
  end

  defp metric_value(row, metric), do: Map.fetch!(row, metric)

  defp metric_label(:revenue), do: gettext("Sales after refunds")
  defp metric_label(:orders), do: gettext("Orders")
  defp metric_label(:avg_check), do: gettext("Average check")

  defp value_label(row, :orders), do: to_string(row.orders)
  defp value_label(row, metric), do: OrderHelpers.money(metric_value(row, metric))

  defp date_label(date), do: Calendar.strftime(date, "%d.%m.%Y")
  defp range_label([]), do: "—"
  defp range_label(rows), do: date_label(hd(rows).from) <> " — " <> date_label(List.last(rows).to)

  defp bucket_label(row, "day"), do: Calendar.strftime(row.from, "%d.%m")
  defp bucket_label(row, "month"), do: Calendar.strftime(row.from, "%m.%Y")

  defp bucket_label(row, "week"),
    do: Calendar.strftime(row.from, "%d.%m") <> "–" <> Calendar.strftime(row.to, "%d.%m")

  defp point_title(row, metric),
    do: date_label(row.from) <> " — " <> date_label(row.to) <> ": " <> value_label(row, metric)

  defp point_data(row, metric),
    do: %{
      value: metric_value(row, metric),
      range: date_label(row.from) <> " — " <> date_label(row.to)
    }
end
