defmodule DelivestWeb.Staff.StatisticsLive.Index do
  use DelivestWeb, :live_view

  alias Delivest.{Analytics, Features, Gateway, Identity}
  alias Delivest.Analytics.Reports
  alias Delivest.Integrations.Channels
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  import DelivestWeb.Staff.StatsComponents
  import DelivestWeb.Staff.StatisticsLive.ReportComponents

  on_mount {DelivestWeb.Hooks.Permission, "statistics.read"}

  @base_tabs ~w(sales products categories)
  @report_tabs ~w(funnel sources customers channels comparison franchise)

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: gettext("Statistics"))}
  end

  @impl true
  def handle_params(params, _url, socket) do
    visible_tabs = visible_tabs(socket)
    tab = if params["tab"] in visible_tabs, do: params["tab"], else: "sales"

    preset =
      if params["period"] in Analytics.presets(), do: params["period"], else: "week"

    {period, period_error} =
      if preset == "custom" do
        case Analytics.validate_custom_period(params["from"], params["to"]) do
          {:ok, period} ->
            {period, nil}

          {:error, :invalid_period} ->
            {Analytics.resolve_period("week", nil, nil, socket.assigns.current_branch.id),
             gettext("Choose a valid period of up to 366 days")}
        end
      else
        {Analytics.resolve_period(preset, nil, nil, socket.assigns.current_branch.id), nil}
      end

    custom_from = if preset == "custom", do: safe_date_param(params["from"]), else: nil
    custom_to = if preset == "custom", do: safe_date_param(params["to"]), else: nil

    sort = if params["sort"] == "quantity", do: :quantity, else: :revenue

    {:noreply,
     socket
     |> assign(
       tab: tab,
       preset: preset,
       period: period,
       period_error: period_error,
       custom_from: custom_from,
       custom_to: custom_to,
       form:
         to_form(%{
           "period" => preset,
           "from" => custom_from,
           "to" => custom_to,
           "channel" => params["channel"],
           "branch_id" => params["branch_id"],
           "link_id" => params["link_id"],
           "link_search" => params["link_search"]
         }),
       sort: sort,
       visible_tabs: visible_tabs,
       report_tabs: @report_tabs,
       link_options:
         if(tab == "sources",
           do:
             Reports.link_options(
               socket.assigns.current_staff,
               socket.assigns.current_branch.id,
               params["link_search"],
               params["link_id"]
             ),
           else: []
         ),
       report_filters: report_filters(params)
     )
     |> then(fn socket -> if period_error, do: socket, else: load_tab(socket) end)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    query =
      %{
        "tab" => socket.assigns.tab,
        "period" => params["period"],
        "sort" => to_string(socket.assigns.sort),
        "channel" => params["channel"] || socket.assigns.report_filters["channel"],
        "branch_id" => params["branch_id"] || socket.assigns.report_filters["branch_id"],
        "link_id" => params["link_id"] || socket.assigns.report_filters["link_id"],
        "link_search" => params["link_search"] || socket.assigns.report_filters["link_search"]
      }
      |> compact_query()
      |> maybe_put_custom(params, socket.assigns.period)

    {:noreply,
     push_patch(socket, to: ~p"/staff/b/#{socket.assigns.current_branch}/statistics?#{query}")}
  end

  @impl true
  def handle_event("rebuild", _, socket) do
    tab = socket.assigns.tab

    result =
      if tab in @report_tabs and tab != "franchise" do
        Reports.request_rebuild(
          socket.assigns.current_staff,
          Reports.feature_for_tab(tab),
          socket.assigns.current_branch.id,
          socket.assigns.period
        )
      else
        {:error, :forbidden}
      end

    case result do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, gettext("Calculation queued")) |> load_tab()}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Calculation could not be queued"))}
    end
  end

  defp maybe_put_custom(query, %{"period" => "custom"} = params, {from, to}) do
    query
    |> Map.put("from", params |> Map.get("from", Date.to_iso8601(from)) |> safe_date_param())
    |> Map.put("to", params |> Map.get("to", Date.to_iso8601(to)) |> safe_date_param())
  end

  defp maybe_put_custom(query, _params, _period), do: query

  defp compact_query(query), do: Map.reject(query, fn {_key, value} -> value in [nil, ""] end)

  defp safe_date_param(value) when is_binary(value) do
    if Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, value), do: value, else: ""
  end

  defp safe_date_param(_value), do: ""

  defp load_tab(%{assigns: %{tab: "sales"}} = socket) do
    %{period: period, current_branch: branch} = socket.assigns
    summary = Analytics.summary(branch.id, period)
    previous = Analytics.summary(branch.id, Analytics.previous_period(period))

    assign(socket,
      summary: summary,
      previous: previous,
      crm_split: Gateway.active?(branch) && Analytics.crm_split(branch.id, period),
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

  defp load_tab(%{assigns: %{tab: tab}} = socket) when tab in @report_tabs do
    scope =
      if tab == "franchise", do: :franchise, else: {:branch, socket.assigns.current_branch.id}

    case Reports.read(
           socket.assigns.current_staff,
           scope,
           socket.assigns.period,
           tab,
           socket.assigns.report_filters
         ) do
      {:ok, report} ->
        previous =
          if tab == "comparison" do
            case Reports.read(
                   socket.assigns.current_staff,
                   scope,
                   Analytics.previous_period(socket.assigns.period),
                   tab,
                   socket.assigns.report_filters
                 ) do
              {:ok, value} -> value
              _ -> nil
            end
          end

        assign(socket, report: report, report_previous: previous)

      _ ->
        assign(socket,
          report: unavailable_report(),
          report_previous: nil
        )
    end
  end

  @doc false
  def unavailable_report do
    %{
      state: :not_collected,
      rows: [],
      last_success_at: nil,
      last_checked_at: nil,
      verified_buyers: nil,
      repeat_buyers: nil,
      retention: nil,
      covered_days: 0,
      expected_days: 0,
      excluded_branches: 0,
      branch_rows: [],
      total_rows: 0,
      page: 1,
      pages: 1,
      totals: %{},
      job: nil
    }
  end

  defp visible_tabs(socket) do
    branch_id = socket.assigns.current_branch.id
    staff = socket.assigns.current_staff

    @base_tabs ++
      Enum.filter(@report_tabs, fn tab ->
        cond do
          tab == "franchise" ->
            Identity.can?(staff, "statistics.network") and
              Features.enabled?("analytics_franchise", :franchise)

          true ->
            Features.enabled?(Reports.feature_for_tab(tab), {:branch, branch_id})
        end
      end)
  end

  defp report_filters(params),
    do: Map.take(params, ["channel", "link_id", "link_search", "branch_ids", "branch_id", "page"])

  defp channel_options do
    [
      {gettext("App"), "app"},
      {gettext("Admin"), "staff"},
      {gettext("POS"), "pos"},
      {gettext("Unknown channel"), "unknown"}
    ]
    |> Kernel.++(Enum.map(Channels.list(), fn {key, name} -> {name, key} end))
    |> Enum.uniq_by(&elem(&1, 1))
  end

  defp tab_path(assigns, tab, overrides \\ %{}) do
    {from, to} = assigns.period

    query =
      %{
        "tab" => tab,
        "period" => assigns.preset,
        "sort" => to_string(assigns.sort),
        "channel" => assigns.report_filters["channel"],
        "branch_id" => assigns.report_filters["branch_id"],
        "link_id" => assigns.report_filters["link_id"],
        "link_search" => assigns.report_filters["link_search"],
        "page" => assigns.report_filters["page"]
      }
      |> compact_query()
      |> then(fn q ->
        if assigns.preset == "custom",
          do:
            Map.merge(q, %{
              "from" => assigns.custom_from || Date.to_iso8601(from),
              "to" => assigns.custom_to || Date.to_iso8601(to)
            }),
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

  defp confirm_time(nil), do: "—"
  defp confirm_time(seconds) when seconds < 60, do: gettext("%{n} s", n: seconds)
  defp confirm_time(seconds), do: gettext("%{n} min", n: Float.round(seconds / 60, 1))

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
            {@current_branch.name}
            <%= if is_nil(@period_error) do %>
              · {format_period(@period)}
            <% end %>
          </p>
        </div>

        <.form
          for={@form}
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
              value={@custom_from}
              class="input input-bordered input-sm w-40"
            />
            <input
              type="date"
              name="to"
              value={@custom_to}
              class="input input-bordered input-sm w-40"
            />
          <% end %>
          <.input
            :if={@tab in ~w(channels comparison franchise)}
            field={@form[:channel]}
            type="select"
            prompt={gettext("All channels")}
            options={channel_options()}
            class="select select-bordered select-sm w-36"
          />
          <.input
            :if={@tab == "franchise"}
            field={@form[:branch_id]}
            type="select"
            prompt={gettext("All branches")}
            options={Enum.map(@staff_branches, &{&1.name, &1.id})}
            class="select select-bordered select-sm w-44"
          />
          <.input
            :if={@tab == "sources"}
            field={@form[:link_search]}
            type="text"
            placeholder={gettext("Find advertising link")}
            class="input input-bordered input-sm w-44"
          />
          <.input
            :if={@tab == "sources"}
            field={@form[:link_id]}
            type="select"
            prompt={gettext("All advertising links")}
            options={@link_options}
            class="input input-bordered input-sm w-56"
          />
        </.form>
      </div>

      <p :if={@period_error} id="statistics-period-error" role="alert" class="text-sm text-error">
        {@period_error}
      </p>

      <div role="tablist" class="tabs tabs-box w-fit">
        <.link
          :for={tab <- @visible_tabs}
          patch={tab_path(assigns, tab)}
          role="tab"
          class={["tab", @tab == tab && "tab-active"]}
        >
          {tab_label(tab)}
        </.link>
      </div>

      <.report_panel
        :if={@tab in @report_tabs and is_nil(@period_error)}
        tab={@tab}
        title={tab_label(@tab)}
        report={@report}
        report_previous={@report_previous}
        current_staff={@current_staff}
        current_branch={@current_branch}
        staff_branches={@staff_branches}
        page_path={fn page -> tab_path(assigns, @tab, %{"page" => Integer.to_string(page)}) end}
      />

      <%= if @tab == "sales" and is_nil(@period_error) do %>
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

        <div :if={@crm_split} id="crm-split" class="grid grid-cols-2 xl:grid-cols-4 gap-3">
          <.stat_card icon="hero-arrows-right-left" label={gettext("Orders via the CRM")}>
            {@crm_split.crm_orders}
          </.stat_card>
          <.stat_card icon="hero-banknotes" label={gettext("Revenue via the CRM")}>
            {OrderHelpers.money(@crm_split.crm_revenue)}
          </.stat_card>
          <.stat_card icon="hero-clock" label={gettext("Time until the CRM took the order")}>
            {confirm_time(@crm_split.avg_confirm_seconds)}
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

      <%= if @tab == "products" and is_nil(@period_error) do %>
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

      <%= if @tab == "categories" and is_nil(@period_error) do %>
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

  defp tab_label("sales"), do: gettext("Sales")
  defp tab_label("products"), do: gettext("Products")
  defp tab_label("categories"), do: gettext("Categories")
  defp tab_label("funnel"), do: gettext("Funnel")
  defp tab_label("sources"), do: gettext("Sources")
  defp tab_label("customers"), do: gettext("Customers")
  defp tab_label("channels"), do: gettext("Channels")
  defp tab_label("comparison"), do: gettext("Comparison")
  defp tab_label("franchise"), do: gettext("Franchise")
end
