defmodule DelivestWeb.Staff.StatisticsLive.ReportComponents do
  use DelivestWeb, :html

  alias Delivest.Identity
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  attr :tab, :string, required: true
  attr :title, :string, required: true
  attr :report, :map, required: true
  attr :report_previous, :any, default: nil
  attr :current_staff, :any, required: true
  attr :current_branch, :any, required: true
  attr :staff_branches, :list, required: true
  attr :page_path, :any, required: true

  def report_panel(assigns) do
    ~H"""
    <section id="statistics-report" class="space-y-4">
      <div class="rounded-2xl border border-base-300 bg-base-100 p-5 space-y-2">
        <div class="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h2 class="text-lg font-semibold">{@title}</h2>
            <p class="text-sm text-base-content/60">{report_explanation(@tab)}</p>
          </div>
          <.link
            :if={@tab == "sources"}
            navigate={~p"/staff/b/#{@current_branch}/advertising-links"}
            class="btn btn-sm btn-outline"
          >
            {gettext("Manage advertising links")}
          </.link>
          <button
            :if={Identity.can?(@current_staff, "admin") and @tab != "franchise"}
            id="statistics-rebuild"
            type="button"
            phx-click="rebuild"
            class="btn btn-sm btn-outline"
          >
            {gettext("Recalculate available history")}
          </button>
        </div>
        <p id="statistics-report-state" class="text-sm" role="status">
          {report_state_label(@report.state)}
          <%= if @report.last_success_at do %>
            · {gettext("Oldest successful bucket calculation")}: {Calendar.strftime(
              @report.last_success_at,
              "%d.%m.%Y %H:%M UTC"
            )}
          <% end %>
        </p>
        <p :if={report_job_state(@report) in [:queued, :running]} class="text-sm text-info">
          {gettext("Calculation is queued or running")}
        </p>
        <p :if={report_job_state(@report) == :error} class="text-sm text-error">
          {gettext("Last calculation failed; the previous published result remains available.")}
        </p>
        <p :if={@report.covered_days < @report.expected_days} class="text-sm text-warning">
          {gettext("Only %{covered} of %{expected} branch days have collected data",
            covered: @report.covered_days,
            expected: @report.expected_days
          )}
        </p>
        <p :if={@report.excluded_branches > 0} class="text-sm text-warning">
          {gettext("%{count} branches are excluded by feature settings",
            count: @report.excluded_branches
          )}
        </p>
      </div>

      <div
        :if={@tab == "franchise" and @report.branch_rows != []}
        class="rounded-2xl border border-base-300 bg-base-100 overflow-x-auto"
      >
        <table id="statistics-branch-comparison" class="table table-sm">
          <thead>
            <tr>
              <th>{gettext("Branch")}</th><th class="text-right">{gettext("Completed")}</th><th class="text-right">
                {gettext("Revenue")}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={branch <- @report.branch_rows}>
              <td>{branch_name(@staff_branches, branch.branch_id)}</td>
              <td class="text-right tabular-nums">{Map.get(branch.counts, "completed", 0)}</td>
              <td class="text-right tabular-nums">
                {OrderHelpers.money(Map.get(branch.counts, "revenue", 0))}
              </td>
            </tr>
          </tbody>
        </table>
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
        id="statistics-funnel-path"
        class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4"
      >
        <div
          :for={stage <- funnel_stages()}
          class="rounded-2xl border border-base-300 bg-base-100 p-4"
        >
          <p class="text-xs text-base-content/60">{stage}</p>
          <p class="text-xl font-semibold tabular-nums">{funnel_value(@report, stage)}</p>
        </div>
        <div class="rounded-2xl border border-base-300 bg-base-100 p-4">
          <p class="text-xs text-base-content/60">{gettext("Sessions with an order")}</p>
          <p class="text-xl font-semibold tabular-nums">
            {funnel_order_value(@report, "converted_sessions")}
          </p>
          <p class="text-xs text-base-content/50">{funnel_conversion(@report)}</p>
        </div>
      </div>

      <div
        :if={@tab == "funnel" and @report.rows != []}
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

      <div
        :if={@report.rows != [] and @tab != "funnel"}
        class="rounded-2xl border border-base-300 bg-base-100 overflow-x-auto"
      >
        <table id="statistics-report-table" class="table table-sm">
          <thead>
            <tr>
              <th>{gettext("Metric")}</th><th>{gettext("Source / channel")}</th>
              <th :if={@tab == "sources"} class="text-right">{gettext("Clicks")}</th>
              <th :if={@tab == "sources"} class="text-right">{gettext("First source clients")}</th>
              <th :if={@tab != "sources"} class="text-right">{gettext("Authorized orders")}</th>
              <th class="text-right">
                {gettext("Created")}
              </th><th class="text-right">{gettext("Completed")}</th><th class="text-right">
                {gettext("Revenue")}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @report.rows}>
              <td>{row.dimension}</td>
              <td class="font-medium">{Map.get(row, :label, row.key)}</td>
              <td :if={@tab == "sources"} class="text-right tabular-nums">
                {Map.get(row.counts, "clicks", 0)}
              </td>
              <td :if={@tab == "sources"} class="text-right tabular-nums">
                {Map.get(row.counts, "first_source_clients", 0)}
              </td>
              <td :if={@tab != "sources"} class="text-right tabular-nums">
                {Map.get(row.counts, "authorized_orders", "—")}
              </td>
              <td class="text-right tabular-nums">
                {Map.get(row.counts, "created", Map.get(row.counts, "sessions", "—"))}
              </td>
              <td class="text-right tabular-nums">{Map.get(row.counts, "completed", "—")}</td>
              <td class="text-right tabular-nums">
                {if Map.has_key?(row.counts, "revenue"),
                  do: OrderHelpers.money(row.counts["revenue"]),
                  else: "—"}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <nav
        :if={@report.pages > 1}
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

  defp branch_name(branches, id) do
    case Enum.find(branches, &(&1.id == id)) do
      nil -> id
      branch -> branch.name
    end
  end

  defp report_total(%{state: :not_collected}, _metric), do: "—"
  defp report_total(report, metric), do: Map.get(report.totals, metric, 0)

  defp report_money(report) do
    case report_total(report, "revenue") do
      amount when is_integer(amount) -> OrderHelpers.money(amount)
      other -> other
    end
  end

  defp funnel_stages,
    do:
      ~w(session_started visit menu_view product_view cart_add checkout_start fulfillment_selected)

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

  defp funnel_value(report, stage) do
    case Enum.find(report.rows, &(&1.dimension == "stage" and &1.key == stage)) do
      nil -> 0
      row -> Map.get(row.counts, "sessions", 0)
    end
  end

  defp funnel_order_value(report, key) do
    case Enum.find(report.rows, &(&1.dimension == "order")) do
      nil -> 0
      row -> Map.get(row.counts, key, 0)
    end
  end

  defp funnel_conversion(report) do
    sessions = funnel_value(report, "session_started")
    converted = funnel_order_value(report, "converted_sessions")
    if sessions > 0, do: "#{Float.round(100 * converted / sessions, 1)}%", else: "—"
  end
end
