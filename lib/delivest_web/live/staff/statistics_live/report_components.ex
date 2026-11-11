defmodule DelivestWeb.Staff.StatisticsLive.ReportComponents do
  use DelivestWeb, :html

  alias Delivest.Identity
  alias Delivest.Integrations.Channels
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
          <%= if @report.last_checked_at do %>
            · {gettext("Last successful check")}: {Calendar.strftime(
              @report.last_checked_at,
              "%d.%m.%Y %H:%M UTC"
            )}
          <% end %>
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
        <div
          :for={{label, value} <- summary_metrics(@report)}
          class="rounded-2xl border border-base-300 bg-base-100 p-4"
        >
          <p class="text-xs text-base-content/60">{label}</p>
          <p class="text-lg font-semibold tabular-nums">{value}</p>
        </div>
      </div>

      <div
        :if={@tab == "franchise" and @report.branch_rows != []}
        class="rounded-2xl border border-base-300 bg-base-100 overflow-x-auto"
      >
        <table id="statistics-branch-comparison" class="table table-sm">
          <thead>
            <tr>
              <th>{gettext("Branch")}</th><th class="text-right">{gettext("Completed")}</th><th class="text-right">
                {gettext("Cancelled")}
              </th><th class="text-right">
                {gettext("Revenue")}
              </th><th class="text-right">{gettext("Average check")}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={branch <- @report.branch_rows}>
              <td>{branch_name(@staff_branches, branch.branch_id)}</td>
              <td class="text-right tabular-nums">{Map.get(branch.counts, "completed", 0)}</td>
              <td class="text-right tabular-nums">{Map.get(branch.counts, "cancelled", 0)}</td>
              <td class="text-right tabular-nums">
                {OrderHelpers.money(Map.get(branch.counts, "revenue", 0))}
              </td>
              <td class="text-right tabular-nums">{average_check(branch.counts)}</td>
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
        class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4"
      >
        <div
          :for={{stage, label} <- funnel_stages()}
          class="rounded-2xl border border-base-300 bg-base-100 p-4"
        >
          <p class="text-xs text-base-content/60">{label}</p>
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
              <th>{gettext("Source / channel")}</th>
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
              <td class="font-medium">{row_label(row, @tab)}</td>
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
      nil -> gettext("Unavailable branch")
      branch -> branch.name
    end
  end

  defp row_label(row, "sources"),
    do: Map.get(row, :label) || gettext("Unavailable advertising link")

  defp row_label(row, _), do: channel_label(row.key)

  defp channel_label("app"), do: gettext("App")
  defp channel_label("staff"), do: gettext("Admin")
  defp channel_label("pos"), do: gettext("POS")
  defp channel_label("unknown"), do: gettext("Unknown channel")

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
      {"visit", gettext("Visits")},
      {"menu_view", gettext("Menu views")},
      {"product_view", gettext("Product views")},
      {"cart_add", gettext("Added to cart")},
      {"checkout_start", gettext("Checkout started")},
      {"fulfillment_selected", gettext("Fulfillment selected")}
    ]
  end

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
