defmodule DelivestWeb.Staff.StatisticsLive.Index do
  use DelivestWeb, :live_view

  alias Delivest.Analytics
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  import DelivestWeb.Staff.StatsComponents

  on_mount {DelivestWeb.Hooks.Permission, "statistics.read"}

  @tabs ~w(sales products categories)

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: gettext("Statistics"))}
  end

  @impl true
  def handle_params(params, _url, socket) do
    tab = if params["tab"] in @tabs, do: params["tab"], else: "sales"

    preset =
      if params["period"] in Analytics.presets(), do: params["period"], else: "week"

    period = Analytics.resolve_period(preset, params["from"], params["to"])
    sort = if params["sort"] == "quantity", do: :quantity, else: :revenue

    {:noreply,
     socket
     |> assign(tab: tab, preset: preset, period: period, sort: sort)
     |> load_tab()}
  end

  @impl true
  def handle_event("filter", params, socket) do
    query =
      %{
        "tab" => socket.assigns.tab,
        "period" => params["period"],
        "sort" => to_string(socket.assigns.sort)
      }
      |> maybe_put_custom(params, socket.assigns.period)

    {:noreply,
     push_patch(socket, to: ~p"/staff/b/#{socket.assigns.current_branch}/statistics?#{query}")}
  end

  defp maybe_put_custom(query, %{"period" => "custom"} = params, {from, to}) do
    query
    |> Map.put("from", present_or(params["from"], Date.to_iso8601(from)))
    |> Map.put("to", present_or(params["to"], Date.to_iso8601(to)))
  end

  defp maybe_put_custom(query, _params, _period), do: query

  defp present_or(value, fallback) when value in [nil, ""], do: fallback
  defp present_or(value, _fallback), do: value

  defp load_tab(%{assigns: %{tab: "sales"}} = socket) do
    %{period: period, current_branch: branch} = socket.assigns
    summary = Analytics.summary(branch.id, period)
    previous = Analytics.summary(branch.id, Analytics.previous_period(period))

    assign(socket,
      summary: summary,
      previous: previous,
      daily: Analytics.daily(branch.id, period),
      hourly: Analytics.hourly(branch.id, period),
      by_fulfillment: Analytics.breakdown(branch.id, period, :fulfillment_type),
      by_payment: Analytics.breakdown(branch.id, period, :payment_method)
    )
  end

  defp load_tab(%{assigns: %{tab: "products"}} = socket) do
    %{period: period, current_branch: branch, sort: sort} = socket.assigns
    assign(socket, products: Analytics.top_products(branch.id, period, limit: 100, sort_by: sort))
  end

  defp load_tab(%{assigns: %{tab: "categories"}} = socket) do
    %{period: period, current_branch: branch} = socket.assigns
    assign(socket, categories: Analytics.categories(branch.id, period))
  end

  defp tab_path(assigns, tab, overrides \\ %{}) do
    {from, to} = assigns.period

    query =
      %{"tab" => tab, "period" => assigns.preset, "sort" => to_string(assigns.sort)}
      |> then(fn q ->
        if assigns.preset == "custom",
          do: Map.merge(q, %{"from" => Date.to_iso8601(from), "to" => Date.to_iso8601(to)}),
          else: q
      end)
      |> Map.merge(overrides)

    ~p"/staff/b/#{assigns.current_branch}/statistics?#{query}"
  end

  defp preset_label("today"), do: gettext("Today")
  defp preset_label("yesterday"), do: gettext("Yesterday")
  defp preset_label("week"), do: gettext("Last 7 days")
  defp preset_label("month"), do: gettext("Last 30 days")
  defp preset_label("this_month"), do: gettext("This month")
  defp preset_label("custom"), do: gettext("Custom")

  defp format_period({from, from}), do: Calendar.strftime(from, "%d.%m.%Y")

  defp format_period({from, to}),
    do: "#{Calendar.strftime(from, "%d.%m.%Y")} — #{Calendar.strftime(to, "%d.%m.%Y")}"

  defp short_date(date), do: Calendar.strftime(date, "%d.%m")

  defp label_every(rows), do: max(div(length(rows) + 11, 12), 1)

  defp breakdown_label(:fulfillment_type, key), do: OrderHelpers.fulfillment_label(key)
  defp breakdown_label(:payment_method, key), do: OrderHelpers.payment_label(key)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 py-4 sm:p-6">
      <div class="flex flex-col lg:flex-row lg:items-end justify-between gap-4">
        <div>
          <h1 class="text-2xl sm:text-3xl font-display font-bold text-base-content">
            {gettext("Statistics")}
          </h1>
          <p class="text-sm text-base-content/60">
            {@current_branch.name} · {format_period(@period)}
          </p>
        </div>

        <.form
          for={%{}}
          id="statistics-filter"
          phx-change="filter"
          class="flex flex-wrap items-center gap-2"
        >
          <select name="period" class="select select-bordered select-sm w-44">
            <option :for={preset <- Analytics.presets()} value={preset} selected={preset == @preset}>
              {preset_label(preset)}
            </option>
          </select>
          <%= if @preset == "custom" do %>
            <input
              type="date"
              name="from"
              value={Date.to_iso8601(elem(@period, 0))}
              class="input input-bordered input-sm w-40"
            />
            <input
              type="date"
              name="to"
              value={Date.to_iso8601(elem(@period, 1))}
              class="input input-bordered input-sm w-40"
            />
          <% end %>
        </.form>
      </div>

      <div role="tablist" class="tabs tabs-box w-fit">
        <.link
          :for={
            {tab, label} <- [
              {"sales", gettext("Sales")},
              {"products", gettext("Products")},
              {"categories", gettext("Categories")}
            ]
          }
          patch={tab_path(assigns, tab)}
          role="tab"
          class={["tab", @tab == tab && "tab-active"]}
        >
          {label}
        </.link>
      </div>

      <%= if @tab == "sales" do %>
        <div class="grid grid-cols-2 xl:grid-cols-4 gap-3">
          <.stat_card
            icon="hero-banknotes"
            label={gettext("Revenue")}
            delta={delta(@summary.revenue, @previous.revenue)}
            hint={delta(@summary.revenue, @previous.revenue) && gettext("vs previous period")}
          >
            {OrderHelpers.money(@summary.revenue)}
          </.stat_card>
          <.stat_card
            icon="hero-shopping-bag"
            label={gettext("Orders")}
            delta={delta(@summary.orders_count, @previous.orders_count)}
            hint={excluded_hint(@summary)}
          >
            {@summary.orders_count}
          </.stat_card>
          <.stat_card
            icon="hero-receipt-percent"
            label={gettext("Average check")}
            delta={delta(@summary.avg_check, @previous.avg_check)}
          >
            {OrderHelpers.money(@summary.avg_check)}
          </.stat_card>
          <.stat_card
            icon="hero-cube"
            label={gettext("Items sold")}
            delta={delta(@summary.items_sold, @previous.items_sold)}
          >
            {@summary.items_sold}
          </.stat_card>
        </div>

        <div class="grid grid-cols-1 xl:grid-cols-2 gap-6">
          <.card class="p-4 space-y-4">
            <h2 class="font-bold">{gettext("Revenue by day")}</h2>
            <.bar_chart
              rows={@daily}
              value={& &1.revenue}
              label={&short_date(&1.date)}
              title={
                &"#{Calendar.strftime(&1.date, "%d.%m.%Y")}: #{OrderHelpers.money(&1.revenue)}, #{&1.orders} #{gettext("orders")}"
              }
              label_every={label_every(@daily)}
            />
          </.card>

          <.card class="p-4 space-y-4">
            <h2 class="font-bold">{gettext("Orders by hour")}</h2>
            <.bar_chart
              rows={@hourly}
              value={& &1.orders}
              label={&"#{&1.hour}"}
              title={
                &"#{&1.hour}:00 — #{&1.orders} #{gettext("orders")}, #{OrderHelpers.money(&1.revenue)}"
              }
              label_every={2}
            />
          </.card>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div
            :for={
              {field, title, rows} <- [
                {:fulfillment_type, gettext("By fulfillment type"), @by_fulfillment},
                {:payment_method, gettext("By payment method"), @by_payment}
              ]
            }
            class="bg-base-100 rounded-box border border-base-300 p-4 space-y-3"
          >
            <h2 class="font-bold">{title}</h2>
            <p :if={rows == []} class="text-sm text-base-content/50">{gettext("No sales")}</p>
            <div :for={row <- rows} class="space-y-1">
              <div class="flex justify-between text-sm">
                <span class="font-medium">{breakdown_label(field, row.key)}</span>
                <span class="text-base-content/60 tabular-nums">
                  {row.orders} · {OrderHelpers.money(row.revenue)}
                </span>
              </div>
              <.share_bar value={row.share} />
            </div>
          </div>
        </div>
      <% end %>

      <%= if @tab == "products" do %>
        <.card class="overflow-x-auto">
          <div class="p-4 flex items-center justify-between gap-3 border-b border-base-200">
            <h2 class="font-bold">{gettext("Products sold")}</h2>
            <div class="join">
              <.link
                patch={tab_path(assigns, "products", %{"sort" => "revenue"})}
                class={["join-item btn btn-xs", @sort == :revenue && "btn-primary"]}
              >
                {gettext("By revenue")}
              </.link>
              <.link
                patch={tab_path(assigns, "products", %{"sort" => "quantity"})}
                class={["join-item btn btn-xs", @sort == :quantity && "btn-primary"]}
              >
                {gettext("By quantity")}
              </.link>
            </div>
          </div>

          <table class="table table-sm">
            <thead>
              <tr>
                <th class="w-10">#</th>
                <th>{gettext("Product")}</th>
                <th>{gettext("Category")}</th>
                <th class="text-right">{gettext("Qty")}</th>
                <th class="text-right">{gettext("Orders")}</th>
                <th class="text-right">{gettext("Revenue")}</th>
                <th class="w-48">{gettext("Share of revenue")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={{row, index} <- Enum.with_index(@products, 1)} class="hover">
                <td class="text-base-content/50 tabular-nums">{index}</td>
                <td class="font-medium">{row.title}</td>
                <td class="text-base-content/60">{row.category_name || "—"}</td>
                <td class="text-right tabular-nums">{row.quantity}</td>
                <td class="text-right tabular-nums">{row.orders}</td>
                <td class="text-right font-mono">{OrderHelpers.money(row.revenue)}</td>
                <td><.share_bar value={row.share} /></td>
              </tr>
              <tr :if={@products == []}>
                <td colspan="7" class="text-center text-base-content/50 py-8">
                  {gettext("No sales in this period")}
                </td>
              </tr>
            </tbody>
          </table>
        </.card>
      <% end %>

      <%= if @tab == "categories" do %>
        <.card class="overflow-x-auto">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>{gettext("Category")}</th>
                <th class="text-right">{gettext("Products")}</th>
                <th class="text-right">{gettext("Qty")}</th>
                <th class="text-right">{gettext("Orders")}</th>
                <th class="text-right">{gettext("Revenue")}</th>
                <th class="w-48">{gettext("Share of revenue")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @categories} class="hover">
                <td class="font-medium">{row.category_name || gettext("Without category")}</td>
                <td class="text-right tabular-nums">{row.products}</td>
                <td class="text-right tabular-nums">{row.quantity}</td>
                <td class="text-right tabular-nums">{row.orders}</td>
                <td class="text-right font-mono">{OrderHelpers.money(row.revenue)}</td>
                <td><.share_bar value={row.share} /></td>
              </tr>
              <tr :if={@categories == []}>
                <td colspan="6" class="text-center text-base-content/50 py-8">
                  {gettext("No sales in this period")}
                </td>
              </tr>
            </tbody>
          </table>
        </.card>
      <% end %>
    </div>
    """
  end

  defp excluded_hint(%{cancelled_count: cancelled, lost_count: lost}) do
    [
      cancelled > 0 && gettext("%{count} cancelled", count: cancelled),
      lost > 0 && gettext("%{count} not delivered to CRM", count: lost)
    ]
    |> Enum.filter(& &1)
    |> Enum.join(", ")
    |> case do
      "" -> nil
      hint -> hint
    end
  end
end
