defmodule DelivestWeb.Staff.DashboardLive.Index do
  use DelivestWeb, :live_view

  alias Delivest.Identity.DashboardLayout
  alias Delivest.Oms.{OrderAttention, Orders}

  alias Delivest.{Analytics, Couriers, Gateway, Identity, LocalTime}
  alias Delivest.Oms.Kitchen
  alias DelivestWeb.Staff.DashboardLive.DayLabel
  alias DelivestWeb.Staff.DashboardLive.Widgets
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  import DelivestWeb.Staff.StatsComponents, only: [delta: 2]

  @active_statuses [:created, :accepted, :preparing, :ready, :delivering]
  @reload_delay :timer.seconds(2)

  @impl true
  def mount(_params, _session, socket) do
    staff = socket.assigns.current_staff
    branches = dashboard_branches(socket)
    dashboard_layout = DashboardLayout.get(staff.id)

    if connected?(socket), do: Enum.each(branches, &Orders.subscribe(&1.id))

    {:ok,
     socket
     |> assign(
       page_title: gettext("Dashboard"),
       can_stats: Identity.can?(staff, "statistics.read"),
       can_orders: Identity.can?(staff, "orders.read"),
       can_create_order: Identity.can?(staff, "orders.create"),
       can_clients: Identity.can?(staff, "clients.read"),
       can_kitchen: Identity.can?(staff, "orders.cook"),
       can_products: Identity.can?(staff, "products.read"),
       dashboard_layout: dashboard_layout,
       saved_layout: dashboard_layout,
       editing_dashboard: false,
       current_branch: socket.assigns[:current_branch],
       dashboard_branches: branches,
       branch_by_id: Map.new(branches, &{&1.id, &1}),
       reload_scheduled: false
     )
     |> load()}
  end

  @impl true
  def handle_info({Orders, _event, _order}, socket), do: {:noreply, schedule_reload(socket)}

  def handle_info(:reload, socket) do
    {:noreply, socket |> assign(reload_scheduled: false) |> load()}
  end

  def handle_info(event, %{assigns: %{live_action: :all}} = socket)
      when event in [:staff_updated, :role_updated] do
    staff = socket.assigns.current_staff
    branches = Identity.list_branch_for_staff(staff)
    previous = MapSet.new(socket.assigns.dashboard_branches, & &1.id)
    current = MapSet.new(branches, & &1.id)

    if connected?(socket) do
      Enum.each(MapSet.difference(previous, current), &Orders.unsubscribe/1)
      Enum.each(MapSet.difference(current, previous), &Orders.subscribe/1)
    end

    {:noreply,
     socket
     |> assign(
       staff_branches: branches,
       dashboard_branches: branches,
       branch_by_id: Map.new(branches, &{&1.id, &1}),
       can_stats: Identity.can?(staff, "statistics.read"),
       can_orders: Identity.can?(staff, "orders.read"),
       can_create_order: Identity.can?(staff, "orders.create"),
       can_clients: Identity.can?(staff, "clients.read"),
       can_kitchen: Identity.can?(staff, "orders.cook"),
       can_products: Identity.can?(staff, "products.read")
     )
     |> load()}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp schedule_reload(%{assigns: %{reload_scheduled: true}} = socket), do: socket

  defp schedule_reload(socket) do
    Process.send_after(self(), :reload, @reload_delay)
    assign(socket, reload_scheduled: true)
  end

  defp load(socket) do
    branches = socket.assigns.dashboard_branches
    now = DateTime.utc_now()

    today =
      LocalTime.today(
        LocalTime.timezone(socket.assigns.current_branch && socket.assigns.current_branch.id)
      )

    socket
    |> assign(today: today)
    |> then(fn socket ->
      if socket.assigns.can_stats do
        rows =
          Enum.map(branches, fn branch ->
            day = LocalTime.today(LocalTime.timezone(branch.id))
            period = {day, day}
            yesterday = Date.add(day, -1)

            local_time =
              now |> DateTime.shift_zone!(LocalTime.timezone(branch.id)) |> DateTime.to_time()

            {Analytics.summary(branch.id, period),
             Analytics.dashboard_summary_to(branch.id, yesterday, local_time),
             Analytics.hourly(branch.id, period),
             Analytics.top_products(branch.id, period, limit: :all)}
          end)

        assign(socket,
          summary: merge_summaries(Enum.map(rows, &elem(&1, 0))),
          yesterday: merge_summaries(Enum.map(rows, &elem(&1, 1))),
          hourly: merge_hourly(Enum.flat_map(rows, &elem(&1, 2))),
          top_products: merge_products(Enum.flat_map(rows, &elem(&1, 3)))
        )
      else
        socket
      end
    end)
    |> then(fn socket ->
      if socket.assigns.can_orders do
        rows =
          Enum.map(branches, fn branch ->
            day = LocalTime.today(LocalTime.timezone(branch.id))
            period = {day, day}
            filters = %{branch_id: branch.id, date_from: day, date_to: day}

            {Analytics.status_counts(branch.id, period), Orders.list_latest_orders(filters, 8),
             OrderAttention.count_for_day(branch.id, day)}
          end)

        counts =
          Enum.reduce(rows, %{}, fn {status, _, _}, acc ->
            Map.merge(acc, status, fn _, a, b -> a + b end)
          end)

        latest =
          rows
          |> Enum.flat_map(&elem(&1, 1))
          |> Enum.sort_by(&{DateTime.to_unix(&1.inserted_at, :microsecond), &1.id}, :desc)
          |> Enum.take(8)

        problem_count = Enum.sum(Enum.map(rows, &elem(&1, 2)))

        assign(socket,
          problem_count: problem_count,
          status_counts: counts,
          in_work: counts |> Map.take(@active_statuses) |> Map.values() |> Enum.sum(),
          latest_orders: latest
        )
      else
        socket
      end
    end)
  end

  defp dashboard_branches(%{assigns: %{live_action: :all}} = socket),
    do: socket.assigns.staff_branches

  defp dashboard_branches(socket), do: [socket.assigns.current_branch]

  defp merge_summaries(rows) do
    totals =
      Enum.reduce(
        rows,
        %{revenue: 0, orders_count: 0, items_sold: 0, cancelled_count: 0, lost_count: 0},
        fn row, acc ->
          Map.new(acc, fn {key, value} -> {key, value + Map.fetch!(row, key)} end)
        end
      )

    Map.put(
      totals,
      :avg_check,
      if(totals.orders_count > 0, do: round(totals.revenue / totals.orders_count), else: 0)
    )
  end

  defp merge_hourly(rows) do
    for hour <- 0..23 do
      matching = Enum.filter(rows, &(&1.hour == hour))

      %{
        hour: hour,
        revenue: Enum.sum(Enum.map(matching, & &1.revenue)),
        orders: Enum.sum(Enum.map(matching, & &1.orders))
      }
    end
  end

  defp merge_products(rows) do
    merged =
      rows
      |> Enum.group_by(& &1.product_id)
      |> Enum.map(fn {id, products} ->
        first = hd(products)

        %{
          product_id: id,
          title: first.title,
          category_name: first.category_name,
          quantity: Enum.sum(Enum.map(products, & &1.quantity)),
          revenue: Enum.sum(Enum.map(products, & &1.revenue)),
          orders: Enum.sum(Enum.map(products, & &1.orders))
        }
      end)
      |> Enum.sort_by(&{&1.revenue, &1.quantity}, :desc)

    total = Enum.sum(Enum.map(merged, & &1.revenue))

    Enum.map(
      Enum.take(merged, 5),
      &Map.put(&1, :share, if(total > 0, do: Float.round(&1.revenue * 100 / total, 1), else: 0.0))
    )
  end

  def staff_page_header(assigns) do
    ~H"""
    <.page_header title={
      if @current_branch,
        do: "#{gettext("Today")}, #{DayLabel.format(@today)}",
        else: gettext("Today")
    }>
      <:actions>
        <button
          :if={!@editing_dashboard}
          id="dashboard-edit"
          type="button"
          phx-click="dashboard_edit"
          class="btn btn-sm btn-outline"
        ><.icon name="hero-pencil-square" class="size-4" />{gettext("Customize")}</button>
        <button
          :if={@editing_dashboard}
          id="dashboard-save"
          type="button"
          phx-click="dashboard_save"
          class="btn btn-sm btn-primary"
        >{gettext("Save layout")}</button>
        <button
          :if={@editing_dashboard}
          id="dashboard-cancel"
          type="button"
          phx-click="dashboard_cancel"
          class="btn btn-sm btn-ghost"
        >{gettext("Cancel")}</button>
        <button
          :if={@editing_dashboard}
          id="dashboard-reset"
          type="button"
          phx-click="dashboard_reset"
          data-confirm={gettext("Restore the default dashboard layout?")}
          class="btn btn-sm btn-ghost"
        >{gettext("Reset to default")}</button>
      </:actions>
    </.page_header>
    """
  end

  @widget_titles %{
    "attention" => "Needs attention",
    "quick_actions" => "Quick actions",
    "revenue" => "Revenue today",
    "orders" => "Orders today",
    "avg_check" => "Average check",
    "in_work" => "In work now",
    "hourly" => "Orders by hour",
    "cumulative_revenue" => "Revenue through the day",
    "latest_orders" => "Latest orders",
    "top_products" => "Best sellers today"
  }

  @action_titles %{
    "new_order" => {"New Order", "hero-plus"},
    "orders" => {"Orders", "hero-shopping-bag"},
    "statistics" => {"Statistics", "hero-chart-bar"},
    "kitchen" => {"Kitchen", "hero-fire"},
    "deliveries" => {"Deliveries", "hero-truck"},
    "stop_list" => {"Stop list", "hero-no-symbol"}
  }

  @impl true
  def handle_event("dashboard_hour", %{"hour" => hour}, socket)
      when is_integer(hour) and hour >= 0 and hour <= 23 do
    if socket.assigns.can_orders && socket.assigns.current_branch do
      {:noreply,
       push_navigate(socket,
         to:
           ~p"/staff/b/#{socket.assigns.current_branch}/orders?#{%{period: "today", hour: hour, sold: true}}"
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("dashboard_hour", _, socket), do: {:noreply, socket}

  @impl true
  def handle_event("dashboard_edit", _params, socket) do
    {:noreply,
     assign(socket, editing_dashboard: true, saved_layout: socket.assigns.dashboard_layout)}
  end

  def handle_event("dashboard_cancel", _params, %{assigns: %{editing_dashboard: true}} = socket) do
    {:noreply,
     assign(socket, editing_dashboard: false, dashboard_layout: socket.assigns.saved_layout)}
  end

  def handle_event(
        "dashboard_layout_change",
        %{"widgets" => widgets},
        %{assigns: %{editing_dashboard: true}} = socket
      ) do
    current = Map.new(socket.assigns.dashboard_layout.widgets, &{&1.id, &1})
    allowed = MapSet.new(allowed_widget_ids(socket.assigns))

    valid? =
      is_list(widgets) and length(widgets) == map_size(current) and
        Enum.all?(widgets, fn
          %{"id" => id, "x" => x, "y" => y, "w" => w, "h" => h} = item ->
            limits = DashboardLayout.widget_limits(id)
            old = Map.get(current, id)

            is_map(old) and is_map(limits) and map_size(item) == 5 and
              is_integer(x) and is_integer(y) and is_integer(w) and is_integer(h) and
              x >= 0 and y >= 0 and y <= 120 and w >= limits.min_w and
              w <= limits.max_w and h >= limits.min_h and h <= limits.max_h and
              x + w <= 12 and
              (MapSet.member?(allowed, id) or old == %{id: id, x: x, y: y, w: w, h: h})

          _ ->
            false
        end) and length(Enum.uniq_by(widgets, & &1["id"])) == length(widgets)

    if valid? do
      updated =
        Map.new(widgets, fn item ->
          {item["id"], %{id: item["id"], x: item["x"], y: item["y"], w: item["w"], h: item["h"]}}
        end)

      ordered = Enum.map(socket.assigns.dashboard_layout.widgets, &Map.fetch!(updated, &1.id))

      {:noreply,
       assign(socket, :dashboard_layout, %{socket.assigns.dashboard_layout | widgets: ordered})}
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "dashboard_add",
        %{"id" => id},
        %{assigns: %{editing_dashboard: true}} = socket
      ) do
    if id in allowed_widget_ids(socket.assigns) and
         not Enum.any?(socket.assigns.dashboard_layout.widgets, &(&1.id == id)) do
      defaults = DashboardLayout.default().widgets
      item = Enum.find(defaults, &(&1.id == id)) || %{id: id, x: 0, y: 0, w: 4, h: 3}

      next_y =
        Enum.reduce(socket.assigns.dashboard_layout.widgets, 0, fn row, acc ->
          max(acc, row.y + row.h)
        end)

      item = %{item | x: 0, y: min(next_y, 120)}

      {:noreply,
       update(socket, :dashboard_layout, fn layout ->
         %{layout | widgets: layout.widgets ++ [item]}
       end)}
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "dashboard_remove",
        %{"id" => id},
        %{assigns: %{editing_dashboard: true}} = socket
      ) do
    if id in allowed_widget_ids(socket.assigns) do
      {:noreply,
       update(socket, :dashboard_layout, fn layout ->
         %{layout | widgets: Enum.reject(layout.widgets, &(&1.id == id))}
       end)}
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "dashboard_action",
        %{"id" => id},
        %{assigns: %{editing_dashboard: true}} = socket
      ) do
    if id in DashboardLayout.action_ids() and id in allowed_action_ids(socket.assigns) do
      {:noreply,
       update(socket, :dashboard_layout, fn layout ->
         actions =
           if id in layout.actions,
             do: List.delete(layout.actions, id),
             else: layout.actions ++ [id]

         %{layout | actions: actions}
       end)}
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "dashboard_move",
        %{"id" => id, "direction" => direction},
        %{assigns: %{editing_dashboard: true}} = socket
      )
      when direction in ["up", "down"] do
    widgets = socket.assigns.dashboard_layout.widgets
    visible = Enum.filter(widgets, &(&1.id in allowed_widget_ids(socket.assigns)))
    index = Enum.find_index(visible, &(&1.id == id))
    other = if direction == "up", do: index && index - 1, else: index && index + 1

    if is_integer(other) and other >= 0 and other < length(visible) do
      first = Enum.at(visible, index)
      second = Enum.at(visible, other)
      swapped = visible |> List.replace_at(index, second) |> List.replace_at(other, first)
      swap_ids = Enum.map(swapped, & &1.id)
      lookup = Map.new(widgets, &{&1.id, &1})

      ordered =
        Enum.map(swap_ids, &Map.fetch!(lookup, &1)) ++ Enum.reject(widgets, &(&1.id in swap_ids))

      {:noreply,
       assign(socket, :dashboard_layout, %{socket.assigns.dashboard_layout | widgets: ordered})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("dashboard_save", _params, %{assigns: %{editing_dashboard: true}} = socket) do
    staff_id = socket.assigns.current_staff.id
    layout = socket.assigns.dashboard_layout
    params = %{"widgets" => layout.widgets, "actions" => layout.actions}

    case DashboardLayout.save(staff_id, params) do
      {:ok, saved} ->
        {:noreply,
         assign(socket,
           dashboard_layout: saved,
           saved_layout: saved,
           editing_dashboard: false
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not save dashboard layout"))}
    end
  end

  def handle_event("dashboard_reset", _params, %{assigns: %{editing_dashboard: true}} = socket) do
    case DashboardLayout.reset(socket.assigns.current_staff.id) do
      {:ok, layout} ->
        {:noreply,
         assign(socket,
           dashboard_layout: layout,
           saved_layout: layout,
           editing_dashboard: false
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not reset dashboard layout"))}
    end
  end

  def handle_event(event, _params, socket)
      when event in [
             "dashboard_cancel",
             "dashboard_layout_change",
             "dashboard_add",
             "dashboard_remove",
             "dashboard_action",
             "dashboard_move",
             "dashboard_save",
             "dashboard_reset"
           ],
      do: {:noreply, socket}

  defp allowed_widget_ids(assigns) do
    Enum.filter(DashboardLayout.widget_ids(), fn id ->
      cond do
        id in ["revenue", "orders", "avg_check", "hourly", "cumulative_revenue", "top_products"] ->
          assigns.can_stats

        id in ["attention", "in_work", "latest_orders"] ->
          assigns.can_orders

        id == "quick_actions" ->
          true

        true ->
          false
      end
    end)
  end

  defp allowed_action_ids(assigns) do
    Enum.filter(DashboardLayout.action_ids(), fn id ->
      cond do
        is_nil(assigns.current_branch) ->
          id == "statistics" and assigns.can_stats and
            Identity.can?(assigns.current_staff, "statistics.network")

        id == "new_order" ->
          assigns.can_create_order

        id == "orders" ->
          assigns.can_orders

        id == "statistics" ->
          assigns.can_stats

        id == "kitchen" ->
          assigns.can_kitchen and Kitchen.working?(assigns.current_branch)

        id == "deliveries" ->
          Identity.can?(assigns.current_staff, "orders.deliver") and
            Gateway.own?(assigns.current_branch, :couriers) and
            (Couriers.own_enabled?(assigns.current_branch.id) or
               Identity.can?(assigns.current_staff, "admin") or
               Couriers.active_for_staff?(assigns.current_staff, assigns.current_branch.id) or
               Couriers.unsettled_for_staff?(assigns.current_staff, assigns.current_branch.id))

        id == "stop_list" ->
          assigns.can_products

        true ->
          false
      end
    end)
  end

  defp action_href("statistics", %{current_branch: nil}), do: ~p"/staff/statistics"
  defp action_href("new_order", assigns), do: ~p"/staff/b/#{assigns.current_branch}/orders/new"
  defp action_href("orders", assigns), do: ~p"/staff/b/#{assigns.current_branch}/orders"
  defp action_href("statistics", assigns), do: ~p"/staff/b/#{assigns.current_branch}/statistics"
  defp action_href("kitchen", assigns), do: ~p"/staff/b/#{assigns.current_branch}/kitchen"
  defp action_href("deliveries", assigns), do: ~p"/staff/b/#{assigns.current_branch}/deliveries"

  defp action_href("stop_list", assigns),
    do: ~p"/staff/b/#{assigns.current_branch}/products/stops"

  defp widget_data(assigns) do
    hourly = assigns[:hourly] || []

    cumulative =
      Enum.map_reduce(hourly, 0, fn row, sum ->
        next = sum + row.revenue
        {%{hour: row.hour, revenue: next}, next}
      end)
      |> elem(0)

    actions =
      assigns.dashboard_layout.actions
      |> Enum.filter(&(&1 in allowed_action_ids(assigns)))
      |> Enum.map(fn id ->
        {title, icon} = Map.fetch!(@action_titles, id)

        %{
          id: id,
          label: Gettext.gettext(DelivestWeb.Gettext, title),
          icon: icon,
          href: action_href(id, assigns)
        }
      end)

    %{
      summary: assigns[:summary],
      revenue_delta:
        assigns[:summary] && delta(assigns.summary.revenue, assigns.yesterday.revenue),
      orders_delta:
        assigns[:summary] && delta(assigns.summary.orders_count, assigns.yesterday.orders_count),
      avg_delta:
        assigns[:summary] && delta(assigns.summary.avg_check, assigns.yesterday.avg_check),
      revenue_hint:
        assigns[:yesterday] &&
          gettext("yesterday by this time %{amount}",
            amount: OrderHelpers.money(assigns.yesterday.revenue)
          ),
      orders_hint:
        assigns[:yesterday] &&
          gettext("yesterday by this time %{count}", count: assigns.yesterday.orders_count),
      cancelled_hint:
        assigns[:status_counts] && Map.get(assigns.status_counts, :cancelled, 0) > 0 &&
          gettext("%{count} cancelled today",
            count: Map.get(assigns.status_counts, :cancelled, 0)
          ),
      in_work: assigns[:in_work],
      problem_count: assigns[:problem_count] || 0,
      created_count: Map.get(assigns[:status_counts] || %{}, :created, 0),
      ready_count: Map.get(assigns[:status_counts] || %{}, :ready, 0),
      problem_href:
        assigns.current_branch && ~p"/staff/b/#{assigns.current_branch}/orders?problem=true",
      created_href:
        assigns.current_branch &&
          ~p"/staff/b/#{assigns.current_branch}/orders?status=created&period=today",
      ready_href:
        assigns.current_branch &&
          ~p"/staff/b/#{assigns.current_branch}/orders?status=ready&period=today",
      actions: actions,
      hourly: hourly,
      cumulative: cumulative,
      hourly_chart: %{
        kind: "hourly",
        title: gettext("Orders by hour"),
        orders_label: gettext("Orders"),
        drilldown: not is_nil(assigns.current_branch) and assigns.can_orders,
        revenue_label: gettext("Revenue") <> " (" <> gettext("Before refunds") <> ")",
        hours: Enum.map(hourly, & &1.hour),
        orders: Enum.map(hourly, & &1.orders),
        revenue: Enum.map(hourly, &OrderHelpers.money(&1.revenue)),
        locale: Gettext.get_locale(DelivestWeb.Gettext)
      },
      cumulative_chart: %{
        kind: "cumulative",
        title: gettext("Revenue through the day"),
        revenue_label: gettext("Revenue") <> " (" <> gettext("Before refunds") <> ")",
        hours: Enum.map(cumulative, & &1.hour),
        values: Enum.map(cumulative, & &1.revenue),
        locale: Gettext.get_locale(DelivestWeb.Gettext)
      },
      top_products: assigns[:top_products] || [],
      products_chart: %{
        kind: "products",
        title: gettext("Best sellers today"),
        share_label: gettext("Share of revenue"),
        revenue_label: gettext("Revenue") <> " (" <> gettext("Before refunds") <> ")",
        quantity_label: gettext("Quantity"),
        products:
          Enum.map(assigns[:top_products] || [], fn row ->
            %{
              name: row.title,
              share: row.share,
              quantity: row.quantity,
              revenue: OrderHelpers.money(row.revenue)
            }
          end),
        locale: Gettext.get_locale(DelivestWeb.Gettext)
      },
      latest_orders: assigns[:latest_orders] || [],
      status_counts: assigns[:status_counts] || %{},
      branch_by_id: assigns.branch_by_id,
      can_clients: assigns.can_clients
    }
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:allowed_widgets, allowed_widget_ids(assigns))
      |> assign(:allowed_actions, allowed_action_ids(assigns))
      |> assign(:widget_data, widget_data(assigns))
      |> assign(:widget_titles, @widget_titles)
      |> assign(:action_titles, @action_titles)
      |> assign(
        :widget_limits,
        Map.new(DashboardLayout.widget_ids(), &{&1, DashboardLayout.widget_limits(&1)})
      )

    ~H"""
    <div id="dashboard-workspace" class="space-y-4">
      <p :if={is_nil(@current_branch)} class="text-sm text-base-content/60">
        {gettext("All branches")}
      </p>
      <section
        :if={@editing_dashboard}
        id="dashboard-catalog"
        class="rounded-box border border-base-300 bg-base-100 p-4 space-y-4"
      >
        <div>
          <h2 class="font-semibold">{gettext("Widget catalog")}</h2><p class="text-sm text-base-content/60">
            {gettext("Choose what appears on your dashboard, then drag or resize the cards.")}
          </p>
        </div>
        <div class="flex flex-wrap gap-2">
          <%= for id <- @allowed_widgets do %>
            <button
              :if={not Enum.any?(@dashboard_layout.widgets, &(&1.id == id))}
              id={"dashboard-add-#{id}"}
              type="button"
              phx-click="dashboard_add"
              phx-value-id={id}
              class="btn btn-sm btn-outline"
            ><.icon name="hero-plus" class="size-4" />{Gettext.gettext(
              DelivestWeb.Gettext,
              Map.fetch!(@widget_titles, id)
            )}</button>
          <% end %>
        </div>
        <div :if={"quick_actions" in @allowed_widgets} class="border-t border-base-200 pt-3">
          <h3 class="text-sm font-semibold mb-2">{gettext("Quick actions")}</h3><div class="flex flex-wrap gap-2">
            <button
              :for={id <- @allowed_actions}
              id={"dashboard-action-#{id}"}
              type="button"
              phx-click="dashboard_action"
              phx-value-id={id}
              class={[
                "btn btn-sm",
                if(id in @dashboard_layout.actions, do: "btn-primary", else: "btn-outline")
              ]}
              aria-pressed={to_string(id in @dashboard_layout.actions)}
            >{Gettext.gettext(DelivestWeb.Gettext, elem(Map.fetch!(@action_titles, id), 0))}</button>
          </div>
        </div>
      </section>

      <div
        id="dashboard-grid-controller"
        phx-hook="DashboardGrid"
        phx-update="ignore"
        data-editing={to_string(@editing_dashboard)}
        data-layout={Jason.encode!(@dashboard_layout.widgets)}
        data-visible={Jason.encode!(@allowed_widgets)}
      >
      </div>
      <div id="dashboard-grid" class={["grid-stack", @editing_dashboard && "dashboard-grid-editing"]}>
        <div
          :for={item <- @dashboard_layout.widgets}
          :if={item.id in @allowed_widgets}
          id={"dashboard-widget-#{item.id}"}
          class="grid-stack-item"
          data-widget-id={item.id}
          gs-id={item.id}
          gs-x={item.x}
          gs-y={item.y}
          gs-w={item.w}
          gs-h={item.h}
          gs-min-w={Map.fetch!(@widget_limits, item.id).min_w}
          gs-max-w={Map.fetch!(@widget_limits, item.id).max_w}
          gs-min-h={Map.fetch!(@widget_limits, item.id).min_h}
          gs-max-h={Map.fetch!(@widget_limits, item.id).max_h}
        >
          <div class="grid-stack-item-content">
            <div :if={@editing_dashboard} class="dashboard-widget-controls">
              <span class="dashboard-drag-handle" role="img" aria-label={gettext("Drag widget")}>⠿</span><span class="text-xs truncate">{Gettext.gettext(
                DelivestWeb.Gettext,
                Map.fetch!(@widget_titles, item.id)
              )}</span><button
                id={"dashboard-move-up-#{item.id}"}
                type="button"
                phx-click="dashboard_move"
                phx-value-id={item.id}
                phx-value-direction="up"
                aria-label={gettext("Move up")}
                class="btn btn-xs btn-ghost"
              ><.icon name="hero-arrow-up" class="size-4" /></button><button
                id={"dashboard-move-down-#{item.id}"}
                type="button"
                phx-click="dashboard_move"
                phx-value-id={item.id}
                phx-value-direction="down"
                aria-label={gettext("Move down")}
                class="btn btn-xs btn-ghost"
              ><.icon name="hero-arrow-down" class="size-4" /></button><button
                id={"dashboard-remove-#{item.id}"}
                type="button"
                phx-click="dashboard_remove"
                phx-value-id={item.id}
                aria-label={gettext("Hide widget")}
                class="btn btn-xs btn-ghost"
              ><.icon name="hero-x-mark" class="size-4" /></button>
            </div>
            <Widgets.widget id={item.id} data={@widget_data} />
          </div>
        </div>
      </div>
      <.card :if={@dashboard_layout.widgets == []} class="p-8 text-center text-base-content/60">
        {gettext("Your dashboard is empty. Customize it to add widgets.")}
      </.card>
    </div>
    """
  end
end
