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
          <h2 class="dashboard-widget-title">
            <%= if @data.problem_count == 0 and @data.created_count == 0 and @data.ready_count == 0 do %>
              <.icon name="hero-check-circle" class="size-5 text-success" />{gettext(
                "Everything is under control"
              )}
            <% else %>
              <.icon name="hero-bell-alert" class="size-5 text-warning" />{gettext("Needs attention")}
            <% end %>
          </h2>
          <div class="grid grid-cols-3 gap-2 mt-4">
            <.attention_count
              id="dashboard-alert-problem"
              label={gettext("Problem orders")}
              count={@data.problem_count}
              href={@data.problem_href}
            />
            <.attention_count
              id="dashboard-alert-waiting"
              label={gettext("To confirm")}
              count={@data.created_count}
              href={@data.created_href}
            />
            <.attention_count
              id="dashboard-alert-ready"
              label={gettext("Ready")}
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
        <.stat_card
          icon="hero-banknotes"
          label={gettext("Revenue today")}
          delta={@data.revenue_delta}
          hint={@data.revenue_hint}
          class="h-full"
        >
          {OrderHelpers.money(@data.summary.revenue)}
        </.stat_card>
      <% "orders" -> %>
        <.stat_card
          icon="hero-shopping-bag"
          label={gettext("Orders today")}
          delta={@data.orders_delta}
          hint={@data.orders_hint}
          class="h-full"
        >
          {@data.summary.orders_count}
        </.stat_card>
      <% "avg_check" -> %>
        <.stat_card
          icon="hero-receipt-percent"
          label={gettext("Average check")}
          delta={@data.avg_delta}
          class="h-full"
        >
          {OrderHelpers.money(@data.summary.avg_check)}
        </.stat_card>
      <% "in_work" -> %>
        <.stat_card
          icon="hero-fire"
          label={gettext("In work now")}
          hint={@data.cancelled_hint}
          class="h-full"
        >
          {@data.in_work}
        </.stat_card>
      <% "hourly" -> %>
        <section class="dashboard-widget-card">
          <h2 class="dashboard-widget-title">{gettext("Orders by hour")}</h2>
          <.analytics_chart
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
                      <th>{gettext("Time")}</th><th>{gettext("Orders")}</th><th>
                        {gettext("Revenue")} ({gettext("Before refunds")})
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={row <- @data.hourly}>
                      <td>{row.hour}:00</td><td>{row.orders}</td><td>
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
          <p :if={@data.top_products == []} class="text-sm text-base-content/50">
            {gettext("No sales yet today")}
          </p>
          <.analytics_chart
            :if={@data.top_products != []}
            id="dashboard-top-products-plot"
            label={gettext("Best sellers today")}
            data={@data.products_chart}
          >
            <details class="text-xs">
              <summary class="cursor-pointer">{gettext("Chart data")}</summary>
              <div class="max-h-48 overflow-auto">
                <table class="table table-xs w-full">
                  <thead>
                    <tr>
                      <th>{gettext("Product")}</th><th>
                        {gettext("Revenue")} ({gettext("Before refunds")})
                      </th><th>{gettext("Quantity")}</th><th>{gettext("Share of revenue")}</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={row <- @data.top_products} id={"dashboard-product-#{row.product_id}"}>
                      <td>{row.title}</td><td>{OrderHelpers.money(row.revenue)}</td><td>
                        {row.quantity}
                      </td><td>{row.share}%</td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </details>
          </.analytics_chart>
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
          <.empty_state :if={@data.latest_orders == []} title={gettext("No orders yet today")} />
          <ul
            :if={@data.latest_orders != []}
            class="divide-y divide-base-200 max-h-full overflow-auto"
          >
            <li
              :for={order <- @data.latest_orders}
              id={"dashboard-order-#{order.id}"}
              class="relative p-3 space-y-1 hover:bg-base-200/60 transition-colors"
            >
              <div class="flex items-center gap-2 min-w-0">
                <.link
                  navigate={
                    ~p"/staff/b/#{Map.fetch!(@data.branch_by_id, order.branch_id)}/orders/#{order.id}"
                  }
                  class="font-mono font-bold after:absolute after:inset-0"
                >#{Order.short_number(order)}</.link><span class="text-xs text-base-content/60 tabular-nums">{OrderHelpers.local_time(
                  order.inserted_at
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
    <% end %>
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
