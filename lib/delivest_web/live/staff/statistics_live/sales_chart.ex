defmodule DelivestWeb.Staff.StatisticsLive.SalesChart do
  use DelivestWeb, :html

  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  attr :daily, :list, required: true
  attr :comparison, :map, default: nil
  attr :granularity, :string, required: true
  attr :metric, :atom, required: true

  def chart(assigns) do
    current = buckets(assigns.daily, assigns.granularity)

    previous =
      if assigns.comparison, do: buckets(assigns.comparison.daily, assigns.granularity), else: []

    scale =
      [1 | Enum.map(current ++ previous, &abs(metric_value(&1, assigns.metric)))] |> Enum.max()

    count = max(length(current), length(previous))

    pairs =
      Enum.zip(
        current ++ List.duplicate(nil, count - length(current)),
        previous ++ List.duplicate(nil, count - length(previous))
      )

    assigns =
      assign(assigns,
        current: current,
        previous: previous,
        scale: scale,
        pairs: pairs,
        signed?:
          assigns.metric in [:revenue, :avg_check] and
            Enum.any?(current ++ previous, &(metric_value(&1, assigns.metric) < 0))
      )

    ~H"""
    <section
      id={"statistics-chart-#{@metric}"}
      class="rounded-box border border-base-300 bg-base-100 p-4"
    >
      <h2 class="font-semibold">{metric_label(@metric)}</h2>
      <p class="mt-1 text-xs text-base-content/60">
        {gettext("Selected period")}: {range_label(@current)}
        <span :if={@comparison}>
          · {gettext("Comparison period")}: {range_label(@previous)}
        </span>
      </p>
      <div class="mt-3 flex gap-4 text-xs">
        <span class="flex items-center gap-1"><span class="h-2.5 w-2.5 rounded bg-primary"></span>{gettext(
          "Selected period"
        )}</span>
        <span :if={@comparison} class="flex items-center gap-1"><span class="h-2.5 w-2.5 rounded bg-secondary"></span>{gettext(
          "Comparison period"
        )}</span>
      </div>
      <p class="mt-2 text-xs tabular-nums text-base-content/60">
        {if(@signed?,
          do:
            "−" <>
              value_label(%{@metric => @scale}, @metric) <>
              " — 0 — +" <> value_label(%{@metric => @scale}, @metric),
          else: "0 — " <> value_label(%{@metric => @scale}, @metric)
        )}
      </p>
      <div class="mt-3 min-w-0 overflow-x-auto" role="group" aria-label={metric_label(@metric)}>
        <div class="flex w-full gap-1 border-b border-base-300 pb-2">
          <div
            :for={{current, previous} <- @pairs}
            class={[(@granularity == "month" && "min-w-12") || "min-w-6", "grow basis-0 text-center"]}
          >
            <div class="relative h-32 border-b border-base-300">
              <div :if={@signed?} class="absolute inset-x-0 top-1/2 border-t border-base-content/30">
              </div>
              <div
                :if={current}
                class="absolute left-1/2 w-2 -translate-x-full rounded-sm bg-primary"
                style={bar_style(current, @metric, @scale, @signed?)}
                title={point_title(current, @metric)}
                aria-label={point_title(current, @metric)}
                data-series="selected"
                data-value={metric_value(current, @metric)}
              >
              </div>
              <div
                :if={previous}
                class="absolute left-1/2 w-2 rounded-sm bg-secondary"
                style={bar_style(previous, @metric, @scale, @signed?)}
                title={point_title(previous, @metric)}
                aria-label={point_title(previous, @metric)}
                data-series="comparison"
                data-value={metric_value(previous, @metric)}
              >
              </div>
            </div>
            <span
              class="mt-1 block text-[10px] tabular-nums"
              title={if(current, do: point_title(current, @metric))}
            >
              {if(current, do: bucket_label(current, @granularity), else: "\u00a0")}
            </span>
            <span
              :if={@comparison}
              class="block text-[10px] tabular-nums text-secondary"
              title={if(previous, do: point_title(previous, @metric))}
            >
              {if(previous, do: bucket_label(previous, @granularity), else: "\u00a0")}
            </span>
          </div>
        </div>
      </div>
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
                <td>{if(current, do: point_title(current, @metric), else: "—")}</td>
                <td :if={@comparison}>
                  {if(previous, do: point_title(previous, @metric), else: "—")}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </details>
    </section>
    """
  end

  @doc false
  def buckets(rows, "month") do
    rows
    |> Enum.group_by(&Date.beginning_of_month(&1.date))
    |> Enum.sort_by(fn {month, _} -> month end)
    |> Enum.map(fn {_month, days} ->
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

  defp bucket_label(row, "month"), do: Calendar.strftime(row.from, "%m.%Y")
  defp bucket_label(row, _), do: Calendar.strftime(row.from, "%d.%m")

  defp point_title(row, metric),
    do: date_label(row.from) <> " — " <> date_label(row.to) <> ": " <> value_label(row, metric)

  defp bar_style(row, metric, scale, signed?) do
    value = metric_value(row, metric)
    height = max(abs(value) / scale * if(signed?, do: 50, else: 100), 1)

    position =
      if(signed? and value < 0, do: "top: 50%", else: "bottom: #{if(signed?, do: 50, else: 0)}%")

    "height: #{height}%; #{position}"
  end
end
