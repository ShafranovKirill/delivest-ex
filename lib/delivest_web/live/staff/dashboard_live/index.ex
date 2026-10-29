defmodule DelivestWeb.Staff.DashboardLive.Index do
  use DelivestWeb, :live_view

  alias Delivest.Oms.Order

  alias Delivest.{Analytics, Identity, LocalTime}
  alias Delivest.Oms.Orders
  alias DelivestWeb.Staff.DashboardLive.DayLabel
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  import DelivestWeb.Staff.StatsComponents

  @active_statuses [:created, :accepted, :preparing, :ready, :delivering]
  @reload_delay :timer.seconds(2)

  @impl true
  def mount(_params, _session, socket) do
    staff = socket.assigns.current_staff
    branch_id = socket.assigns.current_branch.id

    if connected?(socket), do: Orders.subscribe(branch_id)

    {:ok,
     socket
     |> assign(
       page_title: gettext("Dashboard"),
       can_stats: Identity.can?(staff, "statistics.read"),
       can_orders: Identity.can?(staff, "orders.read"),
       can_create_order: Identity.can?(staff, "orders.create"),
       can_clients: Identity.can?(staff, "clients.read"),
       reload_scheduled: false
     )
     |> load()}
  end

  @impl true
  def handle_info({Orders, _event, _order}, socket), do: {:noreply, schedule_reload(socket)}

  def handle_info(:reload, socket) do
    {:noreply, socket |> assign(reload_scheduled: false) |> load()}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp schedule_reload(%{assigns: %{reload_scheduled: true}} = socket), do: socket

  defp schedule_reload(socket) do
    Process.send_after(self(), :reload, @reload_delay)
    assign(socket, reload_scheduled: true)
  end

  defp load(socket) do
    branch_id = socket.assigns.current_branch.id
    today = LocalTime.today(LocalTime.timezone(branch_id))
    today_period = {today, today}
    yesterday = Date.add(today, -1)

    socket
    |> assign(today: today)
    |> then(fn socket ->
      if socket.assigns.can_stats do
        assign(socket,
          summary: Analytics.summary(branch_id, today_period),
          yesterday: Analytics.summary(branch_id, {yesterday, yesterday}),
          hourly: Analytics.hourly(branch_id, today_period),
          top_products: Analytics.top_products(branch_id, today_period, limit: 5)
        )
      else
        socket
      end
    end)
    |> then(fn socket ->
      if socket.assigns.can_orders do
        counts = Analytics.status_counts(branch_id, today_period)

        latest =
          Orders.list_latest_orders(%{branch_id: branch_id, date_from: today, date_to: today}, 8)

        assign(socket,
          status_counts: counts,
          in_work: counts |> Map.take(@active_statuses) |> Map.values() |> Enum.sum(),
          latest_orders: latest
        )
      else
        socket
      end
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 py-4 sm:p-6">
      <div class="flex flex-col sm:flex-row sm:items-end justify-between gap-4">
        <div>
          <p class="text-sm text-base-content/60">{@current_branch.name}</p>
          <h1 class="text-2xl sm:text-3xl font-display font-bold text-base-content">
            {gettext("Today")}, {DayLabel.format(@today)}
          </h1>
        </div>
        <div class="flex flex-wrap gap-2">
          <.link
            :if={@can_create_order}
            navigate={~p"/staff/b/#{@current_branch}/orders/new"}
            class="btn btn-primary btn-sm"
          >
            <.icon name="hero-plus" class="size-4" />
            {gettext("New Order")}
          </.link>
          <.link
            :if={@can_orders}
            navigate={~p"/staff/b/#{@current_branch}/orders"}
            class="btn btn-outline btn-sm"
          >
            <.icon name="hero-shopping-bag" class="size-4" />
            {gettext("Orders")}
          </.link>
          <.link
            :if={@can_stats}
            navigate={~p"/staff/b/#{@current_branch}/statistics"}
            class="btn btn-outline btn-sm"
          >
            <.icon name="hero-chart-bar" class="size-4" />
            {gettext("Statistics")}
          </.link>
        </div>
      </div>

      <div :if={@can_stats or @can_orders} class="grid grid-cols-2 xl:grid-cols-4 gap-3">
        <%= if @can_stats do %>
          <.stat_card
            icon="hero-banknotes"
            label={gettext("Revenue today")}
            delta={delta(@summary.revenue, @yesterday.revenue)}
            hint={gettext("yesterday %{amount}", amount: OrderHelpers.money(@yesterday.revenue))}
          >
            {OrderHelpers.money(@summary.revenue)}
          </.stat_card>
          <.stat_card
            icon="hero-shopping-bag"
            label={gettext("Orders today")}
            delta={delta(@summary.orders_count, @yesterday.orders_count)}
            hint={gettext("yesterday %{count}", count: @yesterday.orders_count)}
          >
            {@summary.orders_count}
          </.stat_card>
          <.stat_card
            icon="hero-receipt-percent"
            label={gettext("Average check")}
            delta={delta(@summary.avg_check, @yesterday.avg_check)}
          >
            {OrderHelpers.money(@summary.avg_check)}
          </.stat_card>
        <% end %>
        <.stat_card
          :if={@can_orders}
          icon="hero-fire"
          label={gettext("In work now")}
          hint={
            Map.get(@status_counts, :cancelled, 0) > 0 &&
              gettext("%{count} cancelled today", count: Map.get(@status_counts, :cancelled, 0))
          }
        >
          {@in_work}
        </.stat_card>
      </div>

      <div class="grid grid-cols-1 xl:grid-cols-3 gap-6 items-start">
        <.card
          :if={@can_orders}
          class="xl:col-span-2"
        >
          <div class="p-4 border-b border-base-200 flex flex-wrap items-center justify-between gap-3">
            <h2 class="font-bold">{gettext("Latest orders")}</h2>
            <div class="flex flex-wrap gap-1.5">
              <span
                :for={status <- [:created, :accepted, :preparing, :ready, :delivering, :completed]}
                :if={Map.get(@status_counts, status, 0) > 0}
                class={["badge badge-sm border", OrderHelpers.status_color(status)]}
              >
                {OrderHelpers.status_label(status)}: {Map.get(@status_counts, status)}
              </span>
            </div>
          </div>

          <.empty_state :if={@latest_orders == []} title={gettext("No orders yet today")} />

          <ul :if={@latest_orders != []} class="divide-y divide-base-200">
            <li
              :for={order <- @latest_orders}
              id={"dashboard-order-#{order.id}"}
              class="relative p-3 sm:p-4 space-y-1 hover:bg-base-200/60 transition-colors"
            >
              <div class="flex items-center gap-2 sm:gap-4">
                <.link
                  navigate={~p"/staff/b/#{@current_branch}/orders/#{order.id}"}
                  class="font-mono font-bold after:absolute after:inset-0"
                >
                  #{Order.short_number(order)}
                </.link>
                <span class="text-sm text-base-content/60 tabular-nums">
                  {OrderHelpers.local_time(order.inserted_at)}
                </span>
                <span class={[
                  "badge badge-sm border",
                  OrderHelpers.status_color(order.status)
                ]}>
                  {OrderHelpers.status_label(order.status)}
                </span>
                <span class="ml-auto font-mono font-bold whitespace-nowrap">
                  {OrderHelpers.money(order.total_amount)}
                </span>
              </div>
              <div class="flex items-center gap-2 text-xs text-base-content/60 min-w-0">
                <span class="shrink-0">{OrderHelpers.fulfillment_label(order.fulfillment_type)}</span>
                <%= if order.client_id do %>
                  <span>·</span>
                  <.link
                    :if={@can_clients}
                    navigate={~p"/staff/clients/#{order.client_id}"}
                    class="relative text-sm text-base-content hover:text-primary hover:underline truncate"
                  >
                    {order.customer_name || order.customer_phone}
                  </.link>
                  <span :if={!@can_clients} class="text-sm text-base-content truncate">
                    {order.customer_name || order.customer_phone}
                  </span>
                <% end %>
              </div>
            </li>
          </ul>
        </.card>

        <div :if={@can_stats} class="space-y-6">
          <.card class="p-4 space-y-3">
            <h2 class="font-bold">{gettext("Best sellers today")}</h2>
            <p :if={@top_products == []} class="text-sm text-base-content/50">
              {gettext("No sales yet today")}
            </p>
            <div :for={row <- @top_products} class="space-y-1">
              <div class="flex justify-between gap-3 text-sm">
                <span class="font-medium truncate">{row.title}</span>
                <span class="text-base-content/60 tabular-nums shrink-0">
                  × {row.quantity} · {OrderHelpers.money(row.revenue)}
                </span>
              </div>
              <.share_bar value={row.share} />
            </div>
          </.card>

          <.card class="p-4 space-y-3">
            <h2 class="font-bold">{gettext("Orders by hour")}</h2>
            <.bar_chart
              rows={@hourly}
              value={& &1.orders}
              label={&"#{&1.hour}"}
              title={&"#{&1.hour}:00 — #{&1.orders}"}
              height="h-28"
              label_every={3}
            />
          </.card>
        </div>
      </div>

      <.card
        :if={!@can_stats and !@can_orders}
        class="p-8 text-center text-base-content/60"
      >
        {gettext("Welcome! Use the menu on the left to get started.")}
      </.card>
    </div>
    """
  end
end
