defmodule DelivestWeb.Staff.DashboardLive.Index do
  use DelivestWeb, :live_view

  alias Delivest.Identity.DashboardLayout
  alias Delivest.Oms.{OrderAttention, Orders}

  alias Delivest.{Analytics, Couriers, Features, Gateway, Identity, LocalTime}
  alias Delivest.Oms.Kitchen
  alias DelivestWeb.Staff.DashboardLive.DayLabel
  alias DelivestWeb.Staff.DashboardLive.Editor
  alias DelivestWeb.Staff.DashboardLive.Widgets
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

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
       can_stats:
         Identity.can?(staff, "statistics.read") and
           Features.enabled?("analytics_basic", dashboard_scope(socket)),
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

  def handle_info(:features_changed, socket) do
    can_stats =
      Identity.can?(socket.assigns.current_staff, "statistics.read") and
        Features.enabled?("analytics_basic", dashboard_scope(socket))

    {:noreply, socket |> assign(can_stats: can_stats) |> load()}
  end

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
       can_stats:
         Identity.can?(staff, "statistics.read") and
           Features.enabled?("analytics_basic", dashboard_scope(socket)),
       can_orders: Identity.can?(staff, "orders.read"),
       can_create_order: Identity.can?(staff, "orders.create"),
       can_clients: Identity.can?(staff, "clients.read"),
       can_kitchen: Identity.can?(staff, "orders.cook"),
       can_products: Identity.can?(staff, "products.read")
     )
     |> load()}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp dashboard_scope(socket) do
    case socket.assigns[:current_branch] do
      %{id: id} -> {:branch, id}
      _ -> :franchise
    end
  end

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

            %{
              branch_id: branch.id,
              summary: Analytics.summary(branch.id, period),
              yesterday: Analytics.dashboard_summary_to(branch.id, yesterday, local_time),
              hourly: Analytics.hourly(branch.id, period),
              yesterday_hourly: Analytics.hourly(branch.id, {yesterday, yesterday}),
              products: Analytics.top_products(branch.id, period, limit: :all),
              local_hour: local_time.hour
            }
          end)

        assign(socket,
          branch_stats: Map.new(rows, &{&1.branch_id, &1.summary}),
          summary: merge_summaries(Enum.map(rows, & &1.summary)),
          yesterday: merge_summaries(Enum.map(rows, & &1.yesterday)),
          hourly: merge_hourly(Enum.flat_map(rows, & &1.hourly)),
          yesterday_hourly: merge_hourly(Enum.flat_map(rows, & &1.yesterday_hourly)),
          current_hour: rows |> Enum.map(& &1.local_hour) |> Enum.max(fn -> -1 end),
          top_products: merge_products(Enum.flat_map(rows, & &1.products))
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

            {branch.id, Analytics.status_counts(branch.id, period),
             Orders.list_latest_orders(filters, 8), OrderAttention.count_for_day(branch.id, day)}
          end)

        counts =
          Enum.reduce(rows, %{}, fn {_, status, _, _}, acc ->
            Map.merge(acc, status, fn _, a, b -> a + b end)
          end)

        latest =
          rows
          |> Enum.flat_map(&elem(&1, 2))
          |> Enum.sort_by(&{DateTime.to_unix(&1.inserted_at, :microsecond), &1.id}, :desc)
          |> Enum.take(8)

        problem_count = Enum.sum(Enum.map(rows, &elem(&1, 3)))

        assign(socket,
          problem_count: problem_count,
          branch_queues:
            Map.new(rows, fn {id, counts, _, problems} ->
              {id, %{counts: counts, problems: problems}}
            end),
          status_counts: counts,
          in_work: counts |> Map.take(@active_statuses) |> Map.values() |> Enum.sum(),
          latest_orders: latest
        )
      else
        socket
      end
    end)
  end

  defp header_statistics_href(assigns) do
    visible_hourly? = Enum.any?(assigns.dashboard_layout.widgets, &(&1.id == "hourly"))

    stats_allowed? =
      "statistics" in allowed_action_ids(assigns) and
        "statistics" in assigns.dashboard_layout.actions

    if stats_allowed? and not visible_hourly?, do: action_href("statistics", assigns)
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
    |> Enum.take(5)
  end

  def staff_page_header(assigns) do
    assigns = assign(assigns, :header_statistics_href, header_statistics_href(assigns))

    ~H"""
    <div id="staff-page-header" class="flex w-full flex-wrap items-center justify-between gap-3">
      <div class="min-w-0">
        <h1 class="text-2xl font-semibold text-base-content">
          {gettext("Today")}, {DayLabel.format(@today)}
        </h1>
        <.link
          :if={@can_stats && @header_statistics_href}
          id="dashboard-header-statistics"
          navigate={@header_statistics_href}
          class="text-sm text-primary hover:underline"
        >{gettext("Statistics")}</.link>
      </div>
      <div id="staff-page-header-actions" class="flex flex-wrap items-center gap-2">
        <button
          :if={!@editing_dashboard}
          id="dashboard-edit"
          type="button"
          phx-click="dashboard_edit"
          class="staff-page-primary-action btn btn-sm btn-outline"
        ><.icon name="hero-pencil-square" class="size-4" />{gettext("Customize")}</button>
        <button
          :if={@editing_dashboard}
          id="dashboard-save"
          type="button"
          phx-click="dashboard_save"
          class="staff-page-primary-action btn btn-sm btn-primary"
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
          class="btn btn-sm btn-ghost"
        >{gettext("Reset to default")}</button>
      </div>
    </div>
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
    "top_products" => "Best sellers today",
    "branch_summary" => "Branches today"
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
    current_widgets = socket.assigns.dashboard_layout.widgets
    current = Map.new(current_widgets, &{&1.id, &1})
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
        Enum.flat_map(widgets, fn %{"id" => id, "x" => x, "y" => y, "w" => w, "h" => h} ->
          if MapSet.member?(allowed, id), do: [%{id: id, x: x, y: y, w: w, h: h}], else: []
        end)

      {ordered, []} =
        Enum.map_reduce(current_widgets, updated, fn item, remaining ->
          if MapSet.member?(allowed, item.id) do
            [next | rest] = remaining
            {next, rest}
          else
            {item, remaining}
          end
        end)

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

      ordered =
        Enum.map(widgets, fn
          ^first -> second
          ^second -> first
          item -> item
        end)

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
    {:noreply, assign(socket, :dashboard_layout, DashboardLayout.default())}
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

        id == "branch_summary" ->
          assigns.live_action == :all and length(assigns.dashboard_branches) > 1 and
            (assigns.can_stats or assigns.can_orders)

        id in ["attention", "in_work", "latest_orders"] ->
          assigns.can_orders

        id == "quick_actions" ->
          assigns.current_branch != nil and
            Enum.any?(allowed_action_ids(assigns), &(&1 != "statistics"))

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
          assigns.can_kitchen and
            Features.enabled?("kitchen", {:branch, assigns.current_branch.id}) and
            Kitchen.working?(assigns.current_branch)

        id == "deliveries" ->
          Features.enabled?("couriers", {:branch, assigns.current_branch.id}) and
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

  defp queue_href(%{current_branch: branch}, query) when not is_nil(branch),
    do: ~p"/staff/b/#{branch}/orders?#{query}"

  defp queue_href(assigns, query) do
    case assigns.dashboard_branches do
      [branch] ->
        ~p"/staff/b/#{branch}/orders?#{query}"

      [branch | _] ->
        path = ~p"/staff/b/#{branch}/orders?#{query}"
        DelivestWeb.StaffBranchPath.selection_path(path, ~p"/staff/dashboard")

      [] ->
        nil
    end
  end

  defp widget_data(assigns) do
    hourly = assigns[:hourly] || []
    yesterday_hourly = assigns[:yesterday_hourly] || []
    hourly_rows = hourly_rows(hourly, yesterday_hourly, assigns[:current_hour] || -1)

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

    statistics_action = Enum.find(actions, &(&1.id == "statistics"))
    quick_actions = Enum.reject(actions, &(&1.id == "statistics"))

    branch_summary =
      Enum.map(assigns.dashboard_branches, fn branch ->
        stats = (assigns[:branch_stats] || %{})[branch.id]
        queue = (assigns[:branch_queues] || %{})[branch.id] || %{counts: %{}, problems: 0}

        %{
          id: branch.id,
          name: branch.name,
          dashboard_href: ~p"/staff/b/#{branch}/dashboard",
          revenue: stats && stats.revenue,
          orders: stats && stats.orders_count,
          problems: queue.problems,
          created: Map.get(queue.counts, :created, 0),
          ready: Map.get(queue.counts, :ready, 0),
          problem_href: ~p"/staff/b/#{branch}/orders?problem=true",
          created_href: ~p"/staff/b/#{branch}/orders?status=created&period=today",
          ready_href: ~p"/staff/b/#{branch}/orders?status=ready&period=today"
        }
      end)

    %{
      summary: assigns[:summary],
      revenue_change: assigns[:summary] && assigns.summary.revenue - assigns.yesterday.revenue,
      revenue_delta:
        assigns[:summary] && percent_delta(assigns.summary.revenue, assigns.yesterday.revenue),
      orders_change:
        assigns[:summary] && assigns.summary.orders_count - assigns.yesterday.orders_count,
      orders_delta:
        assigns[:summary] &&
          percent_delta(assigns.summary.orders_count, assigns.yesterday.orders_count),
      avg_change: assigns[:summary] && assigns.summary.avg_check - assigns.yesterday.avg_check,
      avg_delta:
        assigns[:summary] && percent_delta(assigns.summary.avg_check, assigns.yesterday.avg_check),
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
      problem_href: queue_href(assigns, %{problem: true}),
      created_href: queue_href(assigns, %{status: "created", period: "today"}),
      ready_href: queue_href(assigns, %{status: "ready", period: "today"}),
      actions: quick_actions,
      statistics_action: statistics_action,
      branch_summary: branch_summary,
      can_stats: assigns.can_stats,
      can_orders: assigns.can_orders,
      no_hourly_sales: hourly_rows == [],
      hourly_rows: hourly_rows,
      cumulative: cumulative,
      hourly_chart: %{
        kind: "hourly",
        title: gettext("Orders by hour"),
        orders_label: gettext("Orders"),
        today_label: gettext("Today"),
        yesterday_label: gettext("Yesterday"),
        drilldown: not is_nil(assigns.current_branch) and assigns.can_orders,
        revenue_label: gettext("Revenue") <> " (" <> gettext("Before refunds") <> ")",
        hours: Enum.map(hourly_rows, & &1.hour),
        orders: Enum.map(hourly_rows, & &1.orders),
        yesterday_orders: Enum.map(hourly_rows, & &1.yesterday_orders),
        revenue: Enum.map(hourly_rows, &if(&1.revenue, do: OrderHelpers.money(&1.revenue))),
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
      latest_orders: assigns[:latest_orders] || [],
      status_counts: assigns[:status_counts] || %{},
      branch_by_id: assigns.branch_by_id,
      can_clients: assigns.can_clients
    }
  end

  @doc false
  def hourly_rows(today, yesterday, current_hour) do
    today_by_hour = Map.new(today, &{&1.hour, &1})
    yesterday_by_hour = Map.new(yesterday, &{&1.hour, &1})

    active_hours =
      Enum.flat_map(today, fn row ->
        if row.hour <= current_hour and row.orders > 0, do: [row.hour], else: []
      end) ++
        Enum.flat_map(yesterday, fn row -> if row.orders > 0, do: [row.hour], else: [] end)

    case active_hours do
      [] ->
        []

      hours ->
        for hour <- Enum.min(hours)..Enum.max(hours) do
          today_row = Map.get(today_by_hour, hour, %{orders: 0, revenue: 0})
          yesterday_row = Map.get(yesterday_by_hour, hour, %{orders: 0})

          %{
            hour: hour,
            orders: if(hour <= current_hour, do: today_row.orders),
            yesterday_orders: yesterday_row.orders,
            revenue: if(hour <= current_hour, do: today_row.revenue)
          }
        end
    end
  end

  defp percent_delta(_current, 0), do: nil
  defp percent_delta(current, previous), do: Float.round((current - previous) * 100 / previous, 1)

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

    visible_widgets =
      Enum.filter(assigns.dashboard_layout.widgets, fn item ->
        item.id in assigns.allowed_widgets and
          (item.id != "quick_actions" or assigns.editing_dashboard or
             assigns.widget_data.actions != [])
      end)

    assigns = assign(assigns, :visible_widgets, visible_widgets)

    ~H"""
    <div id="dashboard-workspace" class={[@editing_dashboard && "dashboard-editor-workspace"]}>
      <Editor.catalog
        :if={@editing_dashboard}
        layout={@dashboard_layout}
        allowed_widgets={@allowed_widgets}
        allowed_actions={@allowed_actions}
        widget_titles={@widget_titles}
        action_titles={@action_titles}
      />
      <div class="dashboard-editor-preview min-w-0">
        <div
          id="dashboard-grid-controller"
          phx-hook="DashboardGrid"
          phx-update="ignore"
          data-editing={to_string(@editing_dashboard)}
          data-default-layout={
            to_string(@dashboard_layout.widgets == DashboardLayout.default().widgets)
          }
          data-layout={Jason.encode!(@dashboard_layout.widgets)}
        >
        </div>
        <div
          id="dashboard-grid"
          class={["grid-stack", @editing_dashboard && "dashboard-grid-editing"]}
        >
          <div
            :for={item <- @visible_widgets}
            id={"dashboard-widget-#{item.id}"}
            class="grid-stack-item"
            data-widget-id={item.id}
            data-dashboard-empty={
              to_string(
                !@editing_dashboard and
                  ((item.id == "top_products" and @widget_data.top_products == []) or
                     (item.id == "latest_orders" and @widget_data.latest_orders == []) or
                     (item.id == "attention" and @widget_data.problem_count == 0 and
                        @widget_data.created_count == 0 and @widget_data.ready_count == 0) or
                     (item.id == "hourly" and @widget_data.no_hourly_sales))
              )
            }
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
              <Editor.widget_controls
                :if={@editing_dashboard}
                item={item}
                title={Gettext.gettext(DelivestWeb.Gettext, Map.fetch!(@widget_titles, item.id))}
              />
              <Widgets.widget id={item.id} data={@widget_data} />
            </div>
          </div>
        </div>
        <div
          :if={@visible_widgets != []}
          id="dashboard-grid-loading"
          role="status"
          aria-label={gettext("Loading...")}
        >
          <span class="loading loading-spinner loading-lg" aria-hidden="true"></span>
        </div>
        <.card :if={@visible_widgets == []} class="p-8 text-center text-base-content/60">
          {gettext("Your dashboard is empty. Customize it to add widgets.")}
        </.card>
      </div>
    </div>
    """
  end
end
