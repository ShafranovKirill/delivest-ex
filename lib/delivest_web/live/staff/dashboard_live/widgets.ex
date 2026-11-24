defmodule DelivestWeb.Staff.DashboardLive.Widgets do
  use DelivestWeb, :html

  alias Delivest.Oms.Order
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  import DelivestWeb.Staff.StatsComponents

  attr :id, :string, required: true
  attr :data, :map, required: true

  def widget(assigns) do
    ~H"""
    <%= case @id do %>
      <% "attention" -> %>
        <section id="dashboard-problem-orders" class="dashboard-widget-card border-warning/30">
          <h2
            :if={@data.problem_count == 0 and @data.created_count == 0 and @data.ready_count == 0}
            id="dashboard-attention-empty"
            class="dashboard-widget-title"
          >
            <.icon name="hero-check-circle" class="size-5 text-success" />{gettext(
              "No orders need attention"
            )}
          </h2>
          <h2
            :if={@data.problem_count + @data.created_count + @data.ready_count > 0}
            class="dashboard-widget-title"
          >
            <.icon name="hero-bell-alert" class="size-5 text-warning" />{gettext("Needs attention")}
          </h2>
          <div
            :if={@data.problem_count + @data.created_count + @data.ready_count > 0}
            class="grid grid-cols-3 gap-2 mt-3"
          >
            <.attention_count
              id="dashboard-alert-problem"
              label={gettext("Problem orders")}
              count={@data.problem_count}
              href={@data.problem_href}
            />
            <.attention_count
              id="dashboard-alert-waiting"
              label={gettext("Awaiting confirmation")}
              count={@data.created_count}
              href={@data.created_href}
            />
            <.attention_count
              id="dashboard-alert-ready"
              label={gettext("Ready for handoff")}
              count={@data.ready_count}
              href={@data.ready_href}
            />
          </div>
        </section>
      <% "quick_actions" -> %>
        <section class="dashboard-widget-card">
          <h2 class="dashboard-widget-title">
            <.icon name="hero-bolt" class="size-5 text-primary" />{gettext("Quick actions")}
          </h2>
          <div class="grid grid-cols-2 gap-2 mt-3">
            <.link :for={action <- @data.actions} navigate={action.href} class="dashboard-action-link">
              <.icon name={action.icon} class="size-5" /><span>{action.label}</span>
            </.link>
          </div>
          <p :if={@data.actions == []} class="text-sm text-base-content/60 mt-3">
            {gettext("Choose actions in the catalog")}
          </p>
        </section>
      <% "revenue" -> %>
        <.dashboard_kpi
          icon="hero-banknotes"
          label={gettext("Revenue today")}
          change={@data.revenue_change}
          delta={@data.revenue_delta}
          hint={@data.revenue_hint}
          money
        >
          {OrderHelpers.money(@data.summary.revenue)}
        </.dashboard_kpi>
      <% "orders" -> %>
        <.dashboard_kpi
          icon="hero-shopping-bag"
          label={gettext("Orders today")}
          change={@data.orders_change}
          delta={@data.orders_delta}
          hint={@data.orders_hint}
        >
          {@data.summary.orders_count}
        </.dashboard_kpi>
      <% "avg_check" -> %>
        <.dashboard_kpi
          icon="hero-receipt-percent"
          label={gettext("Average check")}
          change={@data.avg_change}
          delta={@data.avg_delta}
          money
        >
          {OrderHelpers.money(@data.summary.avg_check)}
        </.dashboard_kpi>
      <% "in_work" -> %>
        <.dashboard_kpi
          icon="hero-fire"
          label={gettext("In work now")}
          change={nil}
          hint={@data.cancelled_hint}
        >
          {@data.in_work}
        </.dashboard_kpi>
      <% "hourly" -> %>
        <section class="dashboard-widget-card">
          <div class="flex items-center justify-between gap-3">
            <h2 class="dashboard-widget-title">{gettext("Orders by hour")}</h2>
            <.link
              :if={@data.statistics_action}
              id="dashboard-hourly-statistics"
              navigate={@data.statistics_action && @data.statistics_action.href}
              class="text-xs text-primary hover:underline"
            >{gettext("Statistics")}</.link>
          </div>
          <p
            :if={@data.summary.orders_count == 0}
            id="dashboard-hourly-empty"
            class="mt-3 text-sm text-base-content/60"
          >
            {gettext("No orders yet today")}
          </p>
          <.analytics_chart
            :if={!@data.no_hourly_sales}
            id="dashboard-orders-by-hour-plot"
            label={gettext("Orders by hour")}
            height="h-52"
            data={@data.hourly_chart}
          >
            <details class="text-xs">
              <summary class="cursor-pointer">{gettext("Chart data")}</summary>
              <div class="max-h-48 overflow-auto">
                <table class="table table-xs w-full">
                  <thead>
                    <tr>
                      <th>{gettext("Time")}</th><th>{gettext("Today")}</th><th>
                        {gettext("Yesterday")}
                      </th><th>
                        {gettext("Revenue")} ({gettext("Before refunds")})
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={row <- @data.hourly}>
                      <td>{String.pad_leading(to_string(row.hour), 2, "0")}:00</td><td>
                        {Enum.at(@data.hourly_chart.orders, row.hour) || "—"}
                      </td><td>
                        {Enum.at(@data.yesterday_hourly, row.hour).orders}
                      </td><td>
                        {OrderHelpers.money(row.revenue)}
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </details>
          </.analytics_chart>
        </section>
      <% "cumulative_revenue" -> %>
        <section class="dashboard-widget-card">
          <h2 class="dashboard-widget-title">{gettext("Revenue through the day")}</h2>
          <.analytics_chart
            id="dashboard-cumulative-revenue-plot"
            label={gettext("Revenue through the day")}
            height="h-52"
            data={@data.cumulative_chart}
          >
            <details class="text-xs">
              <summary class="cursor-pointer">{gettext("Chart data")}</summary>
              <div class="max-h-48 overflow-auto">
                <table class="table table-xs w-full">
                  <thead>
                    <tr>
                      <th>{gettext("Time")}</th><th>
                        {gettext("Revenue")} ({gettext("Before refunds")})
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={row <- @data.cumulative}>
                      <td>{row.hour}:00</td><td>{OrderHelpers.money(row.revenue)}</td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </details>
          </.analytics_chart>
        </section>
      <% "top_products" -> %>
        <section class="dashboard-widget-card">
          <h2 class="dashboard-widget-title">{gettext("Best sellers today")}</h2>
          <p
            :if={@data.top_products == []}
            id="dashboard-top-products-empty"
            class="mt-3 text-sm text-base-content/60"
          >
            {gettext("No sales yet today")}
          </p>
          <ol
            :if={@data.top_products != []}
            id="dashboard-top-products-plot"
            class="mt-3 divide-y divide-base-200"
          >
            <li
              :for={{row, rank} <- Enum.with_index(@data.top_products, 1)}
              id={"dashboard-product-#{row.product_id}"}
              class="flex items-center gap-3 py-2 text-sm"
            >
              <span class="w-5 shrink-0 tabular-nums text-base-content/40">{rank}</span>
              <span class="min-w-0 flex-1 truncate font-medium">{row.title}</span>
              <span class="shrink-0 tabular-nums text-base-content/60">{row.quantity} ×</span>
              <span class="shrink-0 tabular-nums font-semibold">{OrderHelpers.money(row.revenue)}</span>
            </li>
          </ol>
        </section>
      <% "latest_orders" -> %>
        <section class="dashboard-widget-card !p-0 overflow-hidden">
          <div class="p-4 border-b border-base-200 flex flex-wrap items-center justify-between gap-3">
            <h2 class="dashboard-widget-title">{gettext("Latest orders")}</h2>
            <div class="flex flex-wrap gap-1.5">
              <span
                :for={status <- [:created, :accepted, :preparing, :ready, :delivering, :completed]}
                :if={Map.get(@data.status_counts, status, 0) > 0}
                class={["badge badge-sm border", OrderHelpers.status_color(status)]}
              >{OrderHelpers.status_label(status)}: {Map.get(@data.status_counts, status)}</span>
            </div>
          </div>
          <p
            :if={@data.latest_orders == []}
            id="dashboard-latest-empty"
            class="p-4 text-sm text-base-content/60"
          >
            {gettext("No orders yet today")}
          </p>
          <ul
            :if={@data.latest_orders != []}
            class="divide-y divide-base-200 max-h-full overflow-auto"
          >
            <li
              :for={order <- @data.latest_orders}
              id={"dashboard-order-#{order.id}"}
              class="relative px-3 py-2 hover:bg-base-200/60 transition-colors"
            >
              <div class="flex items-center gap-2 min-w-0">
                <.link
                  navigate={
                    ~p"/staff/b/#{Map.fetch!(@data.branch_by_id, order.branch_id)}/orders/#{order.id}"
                  }
                  class="font-mono font-bold after:absolute after:inset-0"
                >#{Order.short_number(order)}</.link><span class="text-xs text-base-content/60 tabular-nums">{OrderHelpers.order_time(
                  order.inserted_at,
                  order.branch_id
                )}</span><span class={[
                  "badge badge-sm border",
                  OrderHelpers.status_color(order.status)
                ]}>{OrderHelpers.status_label(order.status)}</span><span class="ml-auto font-mono font-bold whitespace-nowrap">{OrderHelpers.money(
                  order.total_amount
                )}</span>
              </div>
              <div class="flex items-center gap-2 text-xs text-base-content/60 min-w-0">
                <span class="shrink-0">{OrderHelpers.fulfillment_label(order.fulfillment_type)}</span>
                <%= if order.client_id do %>
                  <span>·</span><.link
                    :if={@data.can_clients}
                    navigate={~p"/staff/clients/#{order.client_id}"}
                    class="relative text-sm text-base-content hover:text-primary hover:underline truncate"
                  >{order.customer_name || order.customer_phone}</.link><span
                    :if={!@data.can_clients}
                    class="text-sm text-base-content truncate"
                  >{order.customer_name || order.customer_phone}</span>
                <% end %>
              </div>
            </li>
          </ul>
        </section>
      <% "branch_summary" -> %>
        <section id="dashboard-branch-summary" class="dashboard-widget-card">
          <h2 class="dashboard-widget-title">{gettext("Branches today")}</h2>
          <div class="mt-2 space-y-1.5">
            <div
              :for={branch <- @data.branch_summary}
              id={"dashboard-branch-#{branch.id}"}
              class="rounded-lg border border-base-200 bg-base-200/30 p-2.5"
            >
              <.link
                navigate={branch.dashboard_href}
                class="font-semibold text-primary hover:underline"
              >{branch.name}</.link>
              <div class="mt-1 grid grid-cols-2 gap-x-4 gap-y-1 text-xs sm:grid-cols-3 xl:grid-cols-5">
                <div :if={@data.can_stats} class="min-w-0">
                  <span class="block text-base-content/55">{gettext("Revenue")}</span>
                  <span class="font-semibold tabular-nums">{OrderHelpers.money(branch.revenue)}</span>
                </div>
                <div :if={@data.can_stats}>
                  <span class="block text-base-content/55">{gettext("Orders")}</span>
                  <span class="font-semibold tabular-nums">{branch.orders}</span>
                </div>
                <div :if={@data.can_orders}>
                  <span class="block text-base-content/55">{gettext("Problem orders")}</span>
                  <.link
                    navigate={branch.problem_href}
                    class="font-semibold tabular-nums text-primary hover:underline"
                  >{branch.problems}</.link>
                </div>
                <div :if={@data.can_orders}>
                  <span class="block text-base-content/55">{gettext("Awaiting confirmation")}</span>
                  <.link
                    navigate={branch.created_href}
                    class="font-semibold tabular-nums text-primary hover:underline"
                  >{branch.created}</.link>
                </div>
                <div :if={@data.can_orders}>
                  <span class="block text-base-content/55">{gettext("Ready for handoff")}</span>
                  <.link
                    navigate={branch.ready_href}
                    class="font-semibold tabular-nums text-primary hover:underline"
                  >{branch.ready}</.link>
                </div>
              </div>
            </div>
          </div>
        </section>
    <% end %>
    """
  end

  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :change, :any, required: true
  attr :delta, :any, default: nil
  attr :hint, :string, default: nil
  attr :money, :boolean, default: false
  slot :inner_block, required: true

  defp dashboard_kpi(assigns) do
    ~H"""
    <section class="dashboard-widget-card h-full flex flex-col justify-center gap-1">
      <div class="flex items-center gap-2 text-sm text-base-content/65">
        <.icon name={@icon} class="size-4 text-primary" />
        <span>{@label}</span>
      </div>
      <p class="text-2xl font-semibold tracking-tight tabular-nums sm:text-3xl">
        {render_slot(@inner_block)}
      </p>
      <p class="min-h-4 text-xs text-base-content/60">
        <span
          :if={is_number(@delta)}
          class={[
            @delta > 0 && "text-success",
            @delta < 0 && "text-error",
            "font-medium tabular-nums"
          ]}
        >{if @delta > 0, do: "+"}{@delta}%</span>
        <span
          :if={is_nil(@delta) and is_number(@change) and @change != 0}
          class={[
            @change > 0 && "text-success",
            @change < 0 && "text-error",
            "font-medium tabular-nums"
          ]}
        >{if @change > 0, do: "+"}{if @money, do: OrderHelpers.money(@change), else: @change}</span>
        <span :if={@hint} class="ml-1">{@hint}</span>
      </p>
    </section>
    """
  end

  attr :label, :string, required: true
  attr :id, :string, required: true
  attr :count, :integer, required: true
  attr :href, :string, default: nil

  defp attention_count(assigns) do
    ~H"""
    <div id={@id} class="rounded-lg bg-base-200/60 p-2 min-w-0">
      <p class="text-xl font-bold tabular-nums">{@count}</p>
      <.link :if={@href} navigate={@href} class="text-xs text-primary hover:underline break-words">{@label}</.link>
      <p :if={!@href} class="text-xs text-base-content/60 break-words">{@label}</p>
    </div>
    """
  end
end
