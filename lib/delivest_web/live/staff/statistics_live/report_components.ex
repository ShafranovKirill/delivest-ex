defmodule DelivestWeb.Staff.StatisticsLive.ReportComponents do
  use DelivestWeb, :html

  alias Delivest.Integrations.Channels
  alias DelivestWeb.Staff.OrderLive.OrderHelpers
  import DelivestWeb.Staff.StatsComponents, only: [analytics_chart: 1, stat_card: 1]

  attr :heatmap, :map, required: true
  attr :detail, :any, default: nil
  attr :from, :string, required: true
  attr :to, :string, required: true
  attr :error, :any, default: nil
  attr :fulfillment, :string, required: true
  attr :branch_id, :any, default: nil
  attr :network?, :boolean, required: true

  def heatmap_panel(assigns) do
    assigns =
      assign(assigns, :chart_data, %{
        kind: "heatmap",
        title: gettext("When orders arrive"),
        locale: Gettext.get_locale(DelivestWeb.Gettext),
        days: Enum.map(1..7, &weekday_label/1),
        labels: %{
          total: gettext("Total orders"),
          dates: gettext("Dates"),
          average: gettext("Average per date"),
          scale: gettext("Orders per date"),
          hour: gettext("Local hour")
        },
        cells:
          Enum.map(
            assigns.heatmap.cells,
            &%{
              day: &1.day - 1,
              hour: &1.hour,
              value: &1.average,
              total: &1.total,
              dates: &1.dates
            }
          )
      })

    ~H"""
    <section
      id="statistics-heatmap"
      class="rounded-box border border-base-300 bg-base-100 p-4 space-y-3"
    >
      <h2 class="font-semibold">{gettext("When orders arrive")}</h2>
      <p class="text-xs text-base-content/60">
        {gettext(
          "Includes cancelled orders. Average per calendar weekday, including dates with zero orders."
        )}
        {Date.to_iso8601(elem(@heatmap.period, 0))} — {Date.to_iso8601(elem(@heatmap.period, 1))}
      </p>
      <.form
        for={to_form(%{})}
        id="statistics-heatmap-filter"
        phx-change="heatmap_filter"
        class="flex flex-wrap gap-2"
      >
        <.input
          name="heatmap_from"
          type="date"
          value={@from}
          aria-label={gettext("From Monday")}
          class="input input-bordered input-sm"
        />
        <.input
          name="heatmap_to"
          type="date"
          value={@to}
          aria-label={gettext("Through Sunday")}
          class="input input-bordered input-sm"
        />
        <.input
          name="fulfillment"
          type="select"
          value={@fulfillment}
          options={[
            {gettext("All fulfillment"), "all"},
            {gettext("Delivery"), "delivery"},
            {gettext("Pickup"), "pickup"},
            {gettext("Dine in"), "dine_in"}
          ]}
          aria-label={gettext("Fulfillment")}
          class="select select-bordered select-sm"
        />
        <.input
          :if={@network?}
          name="heatmap_branch"
          type="select"
          value={@branch_id}
          options={[{gettext("All branches"), ""} | Enum.map(@heatmap.branches, &{&1.name, &1.id})]}
          aria-label={gettext("Detail branch")}
          class="select select-bordered select-sm"
        />
      </.form>
      <p :if={@error} id="statistics-heatmap-period-error" role="alert" class="text-sm text-error">
        {@error}
      </p>
      <p :if={@heatmap.state == :no_branches} role="status">{gettext("No accessible branches")}</p>
      <p :if={@heatmap.state == :empty and is_nil(@error)} role="status">
        {gettext("No created orders in this period")}
      </p>
      <.analytics_chart
        :if={!@error}
        id="statistics-heatmap-chart"
        data={@chart_data}
        label={gettext("Average created orders by weekday and local hour")}
        height="h-80"
      >
        <details class="text-xs">
          <summary class="cursor-pointer">{gettext("Chart data")}</summary>
          <div class="max-h-64 overflow-auto">
            <table id="statistics-heatmap-data" class="table table-xs">
              <thead>
                <tr>
                  <th>{gettext("Weekday")}</th><th>{gettext("Local hour")}</th>
                  <th>{gettext("Average per date")}</th><th>{gettext("Total orders")}</th>
                  <th>{gettext("Dates")}</th><th>{gettext("Details")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={cell <- @heatmap.cells}>
                  <td>{weekday_label(cell.day)}</td><td>{cell.hour}:00</td>
                  <td>{format_average(cell.average)}</td><td>{cell.total}</td><td>{cell.dates}</td>
                  <td>
                    <button
                      type="button"
                      class="link link-primary"
                      phx-click="heatmap_detail"
                      phx-value-day={cell.day}
                      phx-value-hour={cell.hour}
                    >
                      {gettext("Dates")}
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </details>
      </.analytics_chart>
      <div :if={@detail} id="statistics-heatmap-detail" class="rounded-lg border border-base-300 p-3">
        <div class="flex justify-between">
          <h3 class="font-semibold">{weekday_label(@detail.day)} · {@detail.hour}:00</h3>
          <button
            type="button"
            phx-click="close_heatmap_detail"
            class="btn btn-xs btn-ghost"
          >{gettext("Close")}</button>
        </div>
        <table class="table table-xs">
          <thead>
            <tr>
              <th>{gettext("Date")}</th><th>{gettext("Created orders")}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @detail.rows}>
              <td>{row.date}</td><td>{row.total}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  attr :rows, :list, required: true
  attr :period, :any, required: true
  attr :metric, :string, required: true

  def comparison_panel(assigns) do
    assigns =
      assign(assigns, :chart_data, %{
        kind: "ranking",
        title: gettext("Branch comparison"),
        metric: assigns.metric,
        locale: Gettext.get_locale(DelivestWeb.Gettext),
        period:
          "#{Date.to_iso8601(elem(assigns.period, 0))} — #{Date.to_iso8601(elem(assigns.period, 1))}",
        labels: %{
          completed: gettext("Completed"),
          calendar_days: gettext("Calendar days"),
          period: gettext("Period")
        },
        rows:
          Enum.map(
            assigns.rows,
            &%{
              name: &1.name,
              value: &1.value,
              days: &1.calendar_days,
              completed: &1.counts["completed"]
            }
          )
      })

    ~H"""
    <section
      id="statistics-branch-comparison-panel"
      class="rounded-box border border-base-300 bg-base-100 p-4 space-y-4"
    >
      <h3 class="font-semibold">{gettext("Branch ranking")}</h3>
      <p class="text-xs text-base-content/60">
        {gettext("Net revenue after successful refunds by order creation date.")} · {Date.to_iso8601(
          elem(@period, 0)
        )} — {Date.to_iso8601(elem(@period, 1))}
      </p>
      <.form for={to_form(%{})} id="statistics-ranking-metric" phx-change="comparison_metric">
        <.input
          name="metric"
          type="select"
          value={@metric}
          options={[
            {gettext("Revenue"), "revenue"},
            {gettext("Completed orders per calendar day"), "orders_per_day"},
            {gettext("Average check"), "avg_check"}
          ]}
          aria-label={gettext("Ranking metric")}
          class="select select-bordered select-sm"
        />
      </.form>
      <p :if={@rows == []} role="status">{gettext("No branch data for this period")}</p>
      <.analytics_chart
        id="statistics-ranking-chart"
        data={@chart_data}
        label={gettext("Branches ranked by selected metric")}
        height="h-80"
      />
    </section>
    """
  end

  defp format_average(value), do: :erlang.float_to_binary(value / 1, decimals: 2)
  defp weekday_label(1), do: gettext("Monday")
  defp weekday_label(2), do: gettext("Tuesday")
  defp weekday_label(3), do: gettext("Wednesday")
  defp weekday_label(4), do: gettext("Thursday")
  defp weekday_label(5), do: gettext("Friday")
  defp weekday_label(6), do: gettext("Saturday")
  defp weekday_label(7), do: gettext("Sunday")

  attr :quality, :map, required: true
  attr :detail, :any, default: nil

  def delivery_quality_panel(assigns) do
    assigns =
      assign(assigns, :chart_data, %{
        kind: "delivery",
        title: gettext("Delivery quality"),
        locale: Gettext.get_locale(DelivestWeb.Gettext),
        labels: %{
          on_time_rate: gettext("On-time rate"),
          coverage: gettext("Measurement coverage"),
          measured: gettext("Measured deliveries"),
          late: gettext("Late deliveries")
        },
        days: Enum.map(assigns.quality.daily, &Map.put(&1, :date, Date.to_iso8601(&1.date)))
      })

    ~H"""
    <section
      id="statistics-delivery-quality"
      class="rounded-box border border-base-300 bg-base-100 p-4 space-y-3"
    >
      <h2 class="font-semibold">{gettext("Delivery quality")}</h2>
      <p class="text-xs text-base-content/60">
        {gettext(
          "Completed deliveries by local order creation date. On-time rate uses only deliveries with a confirmed staff promise and a verified actual delivery event. The original promise is used for revised orders."
        )}
      </p>
      <div class="grid gap-3 sm:grid-cols-3">
        <div>
          <p class="text-xs text-base-content/60">{gettext("On-time rate")}</p><p class="text-xl font-semibold tabular-nums">
            {quality_percent(@quality.summary.on_time_rate)}
          </p><p class="text-xs text-base-content/60">
            {@quality.summary.on_time}/{@quality.summary.measured} {gettext("Measured deliveries")}
          </p>
        </div>
        <div>
          <p class="text-xs text-base-content/60">{gettext("Late deliveries")}</p><p class="text-xl font-semibold tabular-nums">
            {@quality.summary.late}
          </p>
        </div>
        <div>
          <p class="text-xs text-base-content/60">{gettext("Measurement coverage")}</p><p class="text-xl font-semibold tabular-nums">
            {quality_percent(@quality.summary.coverage)}
          </p><p class="text-xs text-base-content/60">
            {@quality.summary.measured}/{@quality.summary.total}
          </p>
        </div>
      </div>
      <p :if={@quality.summary.measured == 0} class="text-sm text-base-content/60" role="status">
        {gettext("No confirmed delivery measurements in this period")}
      </p>
      <.analytics_chart
        id="statistics-delivery-quality-chart"
        data={@chart_data}
        label={gettext("Delivery quality by day")}
        height="h-80"
      >
        <details class="text-xs">
          <summary class="cursor-pointer">{gettext("Chart data")}</summary>
          <div class="max-h-64 overflow-auto">
            <table id="statistics-delivery-quality-data" class="table table-xs w-full">
              <thead>
                <tr>
                  <th>{gettext("Date")}</th><th>{gettext("Completed deliveries")}</th><th>
                    {gettext("Measured deliveries")}
                  </th><th>{gettext("On time")}</th><th>{gettext("Late deliveries")}</th><th>
                    {gettext("Missing measurements")}
                  </th><th>{gettext("On-time rate")}</th><th>{gettext("Measurement coverage")}</th><th>
                    {gettext("Details")}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr :for={day <- @quality.daily}>
                  <td>{day.date}</td><td>{day.total}</td><td>{day.measured}</td><td>{day.on_time}</td><td>
                    {day.late}
                  </td><td>{day.missing}</td><td>{quality_percent(day.on_time_rate)}</td><td>
                    {quality_percent(day.coverage)}
                  </td>
                  <td>
                    <button
                      type="button"
                      phx-click="delivery_day_detail"
                      phx-value-day={day.date}
                      class="link link-primary"
                    >{gettext("Details")}</button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </details>
      </.analytics_chart>
      <div
        :if={@detail}
        id="statistics-delivery-quality-detail"
        class="rounded-lg border border-base-300 p-3"
      >
        <div class="flex items-center justify-between gap-2">
          <h3 class="font-semibold">{@detail.date}</h3>
          <button type="button" phx-click="close_delivery_day_detail" class="btn btn-xs btn-ghost">{gettext(
            "Close"
          )}</button>
        </div>
        <dl class="mt-2 grid gap-2 text-sm sm:grid-cols-3">
          <div>
            <dt>{gettext("Completed deliveries")}</dt><dd class="font-semibold">{@detail.total}</dd>
          </div>
          <div>
            <dt>{gettext("Measured deliveries")}</dt><dd class="font-semibold">{@detail.measured}</dd>
          </div>
          <div>
            <dt>{gettext("On time")}</dt><dd class="font-semibold">{@detail.on_time}</dd>
          </div>
          <div>
            <dt>{gettext("Late deliveries")}</dt><dd class="font-semibold">{@detail.late}</dd>
          </div>
          <div>
            <dt>{gettext("Missing measurements")}</dt><dd class="font-semibold">{@detail.missing}</dd>
          </div>
          <div>
            <dt>{gettext("On-time rate")}</dt><dd class="font-semibold">
              {quality_percent(@detail.on_time_rate)}
            </dd>
          </div>
        </dl>
      </div>
    </section>
    """
  end

  defp quality_percent(nil), do: "—"
  defp quality_percent(value), do: "#{Float.round(value / 1, 1)}%"

  attr :tab, :string, required: true
  attr :title, :string, required: true
  attr :show_title, :boolean, default: true
  attr :report, :map, required: true
  attr :report_previous, :any, default: nil
  attr :refresh_retry?, :boolean, default: false
  attr :current_staff, :any, required: true
  attr :current_branch, :any, required: true
  attr :staff_branches, :list, required: true
  attr :page_path, :any, required: true
  attr :ranking_rows, :list, default: []
  attr :ranking_metric, :string, default: "revenue"
  attr :period, :any, default: nil
  attr :branch_path, :any, default: nil

  def report_panel(assigns) do
    ~H"""
    <section id="statistics-report" class="space-y-4">
      <div class="rounded-xl border border-base-300 bg-base-100 px-3 py-2 space-y-1">
        <div class="flex flex-wrap items-start justify-between gap-2">
          <div :if={@show_title}>
            <h2 :if={@show_title} class="text-lg font-semibold">{@title}</h2>
            <p class="text-sm text-base-content/60">{report_explanation(@tab)}</p>
          </div>
          <.link
            :if={@tab == "sources" and not is_nil(@current_branch)}
            navigate={~p"/staff/b/#{@current_branch}/advertising-links"}
            class="btn btn-sm btn-outline"
          >
            {gettext("Manage advertising links")}
          </.link>
        </div>
        <p id="statistics-report-state" class="text-sm" role="status">
          {report_state_label(@report.state)}
        </p>
        <p
          :if={Map.get(@report, :refresh_pending, false) and not @refresh_retry?}
          id="statistics-report-refreshing"
          class="text-sm text-base-content/60"
          role="status"
        >
          {gettext("Updating report…")}
        </p>
        <p :if={@refresh_retry?} id="statistics-report-refresh-delayed" class="text-sm text-warning">
          {gettext("The report is taking longer to update. Try again shortly.")}
        </p>
        <button
          :if={@refresh_retry? or report_job_state(@report) == :error}
          id="statistics-report-retry"
          type="button"
          phx-click="refresh_report"
          class="btn btn-sm btn-outline"
        >{gettext("Try again")}</button>
        <p :if={report_job_state(@report) == :error} class="text-sm text-error">
          {gettext("The report could not be updated. Previously collected data remains visible.")}
        </p>
        <p :if={@report.covered_days < @report.expected_days} class="text-sm text-warning">
          {gettext("Only %{covered} of %{expected} branch days have complete collection",
            covered: @report.covered_days,
            expected: @report.expected_days
          )}
        </p>
        <p :if={@report.partial_days > 0} class="text-sm text-warning">
          {gettext(
            "Collection was interrupted during %{count} branch days; observed activity remains visible",
            count: @report.partial_days
          )}
        </p>
        <p :if={@report.excluded_branches > 0} class="text-sm text-warning">
          {gettext("%{count} branches are excluded by feature settings",
            count: @report.excluded_branches
          )}
        </p>
      </div>

      <div
        :if={@tab in ~w(sources customers channels comparison franchise)}
        id="statistics-report-summary"
        class="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6"
      >
        <.stat_card :for={{label, value} <- summary_metrics(@report)} label={label}>
          {value}
        </.stat_card>
      </div>

      <.comparison_panel
        :if={@tab == "franchise"}
        rows={@ranking_rows}
        period={@period}
        metric={@ranking_metric}
      />

      <div
        :if={@tab == "franchise" and @report.branch_rows != []}
        class="rounded-2xl border border-base-300 bg-base-100 overflow-x-auto"
      >
        <.table
          id="statistics-branch-comparison"
          rows={@ranking_rows}
          row_id={fn branch -> "statistics-branch-#{branch.branch_id}" end}
        >
          <:col :let={branch} key="branch" label={gettext("Branch")}>
            <.link navigate={@branch_path.(branch.branch_id)} class="link link-primary">
              {branch.name}
            </.link>
          </:col>
          <:col :let={branch} key="completed" label={gettext("Completed")} numeric>
            {Map.get(branch.counts, "completed", 0)}
          </:col>
          <:col :let={branch} key="cancelled" label={gettext("Cancelled")} numeric secondary>
            {Map.get(branch.counts, "cancelled", 0)}
          </:col>
          <:col :let={branch} key="revenue" label={gettext("Revenue")} numeric>
            {OrderHelpers.money(Map.get(branch.counts, "revenue", 0))}
          </:col>
          <:col :let={branch} key="average" label={gettext("Average check")} numeric secondary>
            {average_check(branch.counts)}
          </:col>
          <:col
            :let={branch}
            key="per_day"
            label={gettext("Orders per calendar day")}
            numeric
            secondary
          >
            {format_average(branch.counts["completed"] / branch.calendar_days)}
          </:col>
        </.table>
      </div>

      <div
        :if={@tab == "comparison" and @report_previous}
        id="statistics-period-comparison"
        class="grid gap-3 sm:grid-cols-2"
      >
        <div
          :for={
            {title, value} <- [
              {gettext("Selected period"), @report},
              {gettext("Previous period"), @report_previous}
            ]
          }
          class="rounded-2xl border border-base-300 bg-base-100 p-5"
        >
          <p class="text-sm text-base-content/60">{title} · {report_state_label(value.state)}</p>
          <p class="text-sm">{gettext("Completed")}: {report_total(value, "completed")}</p>
          <p class="text-sm">{gettext("Revenue")}: {report_money(value)}</p>
        </div>
      </div>

      <div
        :if={@tab in ~w(customers franchise)}
        id="statistics-verified-buyers"
        class="rounded-2xl border border-base-300 bg-base-100 p-5"
      >
        <p class="text-sm text-base-content/60">
          {gettext("Identified buyers with completed orders")}
        </p>
        <p class="text-2xl font-semibold tabular-nums">{@report.verified_buyers || "—"}</p>
        <div class="mt-3 grid gap-2 sm:grid-cols-2 text-sm">
          <p>
            {gettext("Repeat identified buyers")}: <strong>{@report.repeat_buyers || "—"}</strong>
          </p>
          <p>
            {gettext("Retention from previous equal period")}:
            <strong>{if @report.retention, do: "#{@report.retention}%", else: "—"}</strong>
          </p>
        </div>
        <p class="text-xs text-base-content/50">
          {gettext(
            "Only verified client IDs are counted across channels; guest phone numbers are not matched."
          )}
        </p>
        <p class="text-xs text-base-content/50">
          {gettext(
            "Percentage of authorized buyers is unavailable: anonymous buyers cannot be counted reliably."
          )}
        </p>
      </div>

      <div
        :if={@tab == "funnel" and @report.rows != []}
        id="statistics-funnel-sources"
        class="rounded-2xl border border-base-300 bg-base-100 p-5"
      >
        <h3 class="font-semibold">{gettext("Observed session sources")}</h3>
        <dl class="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-4">
          <div :for={{key, label} <- funnel_sources()}>
            <dt class="text-xs text-base-content/60">{label}</dt>
            <dd class="font-semibold tabular-nums">{funnel_source_value(@report, key)}</dd>
          </div>
        </dl>
        <p class="mt-3 text-xs text-base-content/50">
          {gettext(
            "These first-event labels are unverified observations, not confirmed advertising attribution."
          )}
        </p>
      </div>

      <div
        :if={@tab == "funnel" and @report.rows != []}
        id="statistics-funnel-path"
        class="rounded-2xl border border-base-300 bg-base-100 p-4 space-y-3"
      >
        <h3 class="font-semibold">{gettext("Order funnel")}</h3>
        <p :if={Map.get(@report, :legacy_days, 0) > 0} class="text-sm text-warning">
          {gettext("Legacy funnel days are excluded until refreshed.")}
        </p>
        <.analytics_chart
          id="statistics-funnel-chart"
          label={gettext("Order funnel")}
          height="h-80"
          data={
            %{
              kind: "funnel",
              title: gettext("Order funnel"),
              locale: Gettext.get_locale(DelivestWeb.Gettext),
              labels: %{
                previous: gettext("From previous step"),
                start: gettext("From start"),
                lost: gettext("Lost before next step")
              },
              stages:
                Enum.map(funnel_stages(), fn {key, label} ->
                  counts = funnel_stage_counts(@report, key)

                  %{
                    name: label,
                    sessions: Map.get(counts, "sessions", 0),
                    previous: Map.get(counts, "from_previous_percent"),
                    start: Map.get(counts, "from_start_percent"),
                    lost: Map.get(counts, "lost_to_next")
                  }
                end)
            }
          }
        >
          <details class="text-xs">
            <summary class="cursor-pointer">{gettext("Chart data")}</summary>
            <div class="overflow-x-auto">
              <table id="statistics-funnel-data" class="table table-xs w-full">
                <thead>
                  <tr>
                    <th>{gettext("Stage")}</th><th>{gettext("Sessions")}</th><th>
                      {gettext("From previous step")}
                    </th><th>{gettext("From start")}</th><th>{gettext("Lost before next step")}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={{key, label} <- funnel_stages()}>
                    <% counts = funnel_stage_counts(@report, key) %>
                    <td>{label}</td><td>{Map.get(counts, "sessions", 0)}</td>
                    <td>{funnel_percent(counts["from_previous_percent"])}</td>
                    <td>{funnel_percent(counts["from_start_percent"])}</td>
                    <td>{Map.get(counts, "lost_to_next") || "—"}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </details>
        </.analytics_chart>
      </div>

      <div
        :if={@tab == "funnel" and Enum.any?(@report.rows, &(&1.dimension == "order"))}
        id="statistics-funnel-outcomes"
        class="rounded-2xl border border-base-300 bg-base-100 p-5"
      >
        <h3 class="font-semibold">{gettext("Order outcomes for this session cohort")}</h3>
        <dl class="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-4">
          <div :for={{label, key} <- funnel_outcomes()}>
            <dt class="text-xs text-base-content/60">{label}</dt>
            <dd class="font-semibold tabular-nums">{funnel_order_value(@report, key)}</dd>
          </div>
        </dl>
        <p class="mt-3 text-xs text-base-content/50">
          {gettext(
            "Unlinked orders use creation date and are shown separately; they are not included in session conversion."
          )}
        </p>
      </div>

      <.table
        :if={@report.rows != [] and @tab != "funnel"}
        id="statistics-report-rows"
        rows={@report.rows}
        show_column_chooser={false}
      >
        <:col :let={row} label={gettext("Source / channel")}>{row_label(row, @tab)}</:col>
        <:col :let={row} :if={@tab == "sources"} label={gettext("Clicks")} numeric>
          {Map.get(row.counts, "clicks", 0)}
        </:col>
        <:col :let={row} :if={@tab == "sources"} label={gettext("First source clients")} numeric>
          {Map.get(row.counts, "first_source_clients", 0)}
        </:col>
        <:col :let={row} :if={@tab != "sources"} label={gettext("Authorized orders")} numeric>
          {Map.get(row.counts, "authorized_orders", "—")}
        </:col>
        <:col :let={row} label={gettext("Created")} numeric>
          {Map.get(row.counts, "created", Map.get(row.counts, "sessions", "—"))}
        </:col>
        <:col :let={row} label={gettext("Completed")} numeric>
          {Map.get(row.counts, "completed", "—")}
        </:col>
        <:col :let={row} label={gettext("Revenue")} numeric>
          {if Map.has_key?(row.counts, "revenue"),
            do: OrderHelpers.money(row.counts["revenue"]),
            else: "—"}
        </:col>
      </.table>
      <nav
        :if={@report.pages > 1 and @tab != "franchise"}
        id="statistics-report-pagination"
        class="flex items-center justify-end gap-3 text-sm"
      >
        <.link
          :if={@report.page > 1}
          patch={@page_path.(@report.page - 1)}
          class="btn btn-sm btn-outline"
        >{gettext("Previous")}</.link>
        <span>{@report.page} / {@report.pages}</span>
        <.link
          :if={@report.page < @report.pages}
          patch={@page_path.(@report.page + 1)}
          class="btn btn-sm btn-outline"
        >{gettext("Next")}</.link>
      </nav>
    </section>
    """
  end

  defp report_state_label(:not_collected), do: gettext("Data was not collected for this period")
  defp report_state_label(:partial), do: gettext("Partial data")
  defp report_state_label(:empty), do: gettext("No activity in collected period")
  defp report_state_label(:stale), do: gettext("Data may be stale")
  defp report_state_label(_), do: gettext("Updated")

  def report_description(tab), do: report_explanation(tab)

  defp report_explanation("funnel"),
    do:
      gettext(
        "Session steps are observational; orders and payment stages use server records. Cash is shown separately from confirmed online payments."
      )

  defp report_explanation("sources"),
    do:
      gettext(
        "Only saved advertising link receipts are confirmed attribution. UTM labels are unverified."
      )

  defp report_explanation(_),
    do:
      gettext(
        "Revenue includes completed orders net of succeeded refunds, grouped by order creation date. No causal effect is inferred from channel differences."
      )

  defp report_job_state(%{job: {:ok, %{state: state}}}), do: state
  defp report_job_state(_), do: nil

  defp row_label(row, "sources"),
    do: Map.get(row, :label) || gettext("Unavailable advertising link")

  defp row_label(row, _), do: channel_label(row.key)

  defp channel_label("app"), do: gettext("Storefront")
  defp channel_label("staff"), do: gettext("Admin")
  defp channel_label("pos"), do: gettext("POS")
  defp channel_label("unknown"), do: gettext("Unknown channel")
  defp channel_label("other"), do: gettext("Other")

  defp channel_label(key) do
    case Ecto.UUID.cast(key) do
      {:ok, _} -> gettext("Unknown channel")
      _ -> Channels.name(key)
    end
  end

  defp summary_metrics(report) do
    [
      {gettext("Created"), report_total(report, "created")},
      {gettext("Completed"), report_total(report, "completed")},
      {gettext("Cancelled"), report_total(report, "cancelled")},
      {gettext("Net revenue"), report_money(report, "revenue")},
      {gettext("Refunded"), report_money(report, "refunded")},
      {gettext("Average check"), average_check(report.totals, report.state)}
    ]
  end

  defp average_check(totals), do: average_check(totals, :ready)

  defp average_check(_totals, :not_collected), do: "—"

  defp average_check(totals, _state) do
    completed = Map.get(totals, "completed", 0)
    revenue = Map.get(totals, "revenue", 0)

    if completed > 0,
      do: OrderHelpers.money(div(revenue + div(completed, 2), completed)),
      else: "—"
  end

  defp report_total(%{state: :not_collected}, _metric), do: "—"
  defp report_total(report, metric), do: Map.get(report.totals, metric, 0)

  defp report_money(report), do: report_money(report, "revenue")

  defp report_money(report, key) do
    case report_total(report, key) do
      amount when is_integer(amount) -> OrderHelpers.money(amount)
      other -> other
    end
  end

  defp funnel_stages do
    [
      {"session_started", gettext("Sessions started")},
      {"menu_view", gettext("Menu views")},
      {"cart_add", gettext("Added to cart")},
      {"checkout_start", gettext("Checkout started")},
      {"order_created", gettext("Orders created")}
    ]
  end

  defp funnel_stage_counts(report, key) do
    case Enum.find(report.rows, &(&1.dimension == "stage" and &1.key == key)) do
      nil -> %{}
      row -> row.counts
    end
  end

  defp funnel_percent(nil), do: "—"
  defp funnel_percent(value), do: "#{value}%"

  defp funnel_sources do
    [
      {"direct", gettext("Direct visit")},
      {"campaign", gettext("Campaign label (unverified)")},
      {"unknown", gettext("Unknown source")},
      {"unavailable", gettext("Source data unavailable")}
    ]
  end

  defp funnel_source_value(report, key) do
    case Enum.find(report.rows, &(&1.dimension == "session_source" and &1.key == key)) do
      nil -> 0
      row -> Map.get(row.counts, "sessions", 0)
    end
  end

  defp funnel_outcomes do
    [
      {gettext("Orders created"), "created"},
      {gettext("Awaiting payment"), "awaiting_payment"},
      {gettext("Online paid sessions"), "paid_online_sessions"},
      {gettext("Cash method orders"), "cash_method"},
      {gettext("Completed orders"), "completed"},
      {gettext("Cancelled orders"), "cancelled"},
      {gettext("Unlinked orders on creation date"), "unlinked_orders_created_day"}
    ]
  end

  defp funnel_order_value(report, key) do
    case Enum.find(report.rows, &(&1.dimension == "order")) do
      nil -> 0
      row -> Map.get(row.counts, key, 0)
    end
  end
end
