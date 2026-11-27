defmodule DelivestWeb.Staff.StatisticsLive.Index do
  use DelivestWeb, :live_view

  alias Delivest.{Analytics, Features, Identity}
  alias Delivest.Analytics.{BranchComparison, DeliveryQuality, OrderHeatmap, Overview, Reports}
  alias Delivest.Integrations.Channels
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  import DelivestWeb.Staff.StatsComponents
  import DelivestWeb.Staff.StatisticsLive.ReportComponents
  import DelivestWeb.Staff.StatisticsLive.SalesChart

  on_mount {DelivestWeb.Hooks.Permission, "statistics.read"}

  @base_tabs ~w(overview sales products categories orders cancelled refunds)
  @report_tabs ~w(funnel sources customers channels comparison franchise)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket),
      do: Phoenix.PubSub.subscribe(Delivest.PubSub, "analytics:visibility")

    {:ok,
     socket
     |> assign(
       page_title: gettext("Statistics"),
       refresh_timer: nil,
       refresh_epoch: 0,
       refresh_attempts: 0,
       refresh_retry?: false
     )
     |> attach_hook(:analytics_scope_permissions, :handle_info, &recheck_permissions/2)}
  end

  defp recheck_permissions(event, socket) when event in [:role_updated, :staff_updated] do
    staff = socket.assigns.current_staff

    if Identity.can?(staff, "statistics.read") and
         (not socket.assigns[:global_statistics?] or Identity.can?(staff, "statistics.network")) do
      branches = Identity.list_branch_for_staff(staff)
      socket = assign(socket, :staff_branches, branches)

      if socket.assigns[:current_branch] &&
           not Enum.any?(branches, &(&1.id == socket.assigns.current_branch.id)) do
        {:halt,
         redirect(cancel_report_refresh(socket),
           to: DelivestWeb.StaffBranchPath.home(List.first(branches))
         )}
      else
        {:cont,
         if(socket.assigns[:tab] && is_nil(socket.assigns[:period_error]),
           do: load_tab(socket),
           else: socket
         )}
      end
    else
      {:halt,
       redirect(socket, to: DelivestWeb.StaffBranchPath.home(socket.assigns[:current_branch]))}
    end
  end

  defp recheck_permissions(_, socket), do: {:cont, socket}

  @impl true
  def handle_params(params, url, socket) do
    params = sanitize_branch_filter(params)
    socket = cancel_report_refresh(socket)

    socket =
      assign(socket,
        refresh_epoch: socket.assigns.refresh_epoch + 1,
        refresh_attempts: 0,
        refresh_retry?: false,
        heatmap_detail: nil
      )

    global? = not String.starts_with?(URI.parse(url).path, "/staff/b/")
    section = params["section"]
    legacy_tab = params["tab"]
    branch = if global?, do: nil, else: socket.assigns.current_branch
    socket = assign(socket, current_branch: branch, global_statistics?: global?, section: section)

    legacy_branch =
      if global? and is_binary(params["branch_id"]),
        do:
          Enum.find(
            socket.assigns.staff_branches,
            &(&1.id == params["branch_id"] || &1.slug == params["branch_id"])
          ),
        else: nil

    cond do
      legacy_branch ->
        query = params |> Map.drop(["branch_id", "branch_slug", "section"]) |> scalar_query()
        destination = if section, do: "analytics/#{section}", else: "statistics"

        {:noreply,
         redirect(socket,
           to:
             "/staff/b/#{legacy_branch.slug}/#{destination}?" <>
               Plug.Conn.Query.encode(query)
         )}

      global? and Map.has_key?(params, "branch_id") ->
        query = params |> Map.drop(["branch_id", "branch_slug", "section"]) |> scalar_query()
        destination = if section, do: "analytics/#{section}", else: "statistics"

        if Identity.can?(socket.assigns.current_staff, "statistics.network") do
          {:noreply,
           redirect(socket, to: "/staff/#{destination}?" <> Plug.Conn.Query.encode(query))}
        else
          {:noreply,
           redirect(socket,
             to: DelivestWeb.StaffBranchPath.home(List.first(socket.assigns.staff_branches))
           )}
        end

      global? and not Identity.can?(socket.assigns.current_staff, "statistics.network") ->
        {:noreply,
         redirect(socket,
           to: DelivestWeb.StaffBranchPath.home(List.first(socket.assigns.staff_branches))
         )}

      is_nil(section) and legacy_tab in @report_tabs ->
        section = if legacy_tab == "franchise", do: "comparison", else: legacy_tab
        query = Map.drop(params, ["tab", "branch_slug"])
        query = if legacy_tab == "comparison", do: Map.put(query, "compare", "true"), else: query

        destination =
          if legacy_tab == "comparison", do: "statistics", else: "analytics/#{section}"

        prefix =
          if branch && legacy_tab != "franchise", do: "/staff/b/#{branch.slug}/", else: "/staff/"

        {:noreply,
         redirect(socket, to: prefix <> destination <> "?" <> Plug.Conn.Query.encode(query))}

      section != nil and section not in ~w(channels sources funnel customers comparison) ->
        {:noreply, redirect(socket, to: "/staff/statistics")}

      section != nil and visible_tabs(socket) == [] ->
        query =
          params
          |> Map.take(~w(period from to compare compare_from compare_to))
          |> Enum.filter(fn {_key, value} -> is_binary(value) end)
          |> Map.new()

        prefix = if branch, do: "/staff/b/#{branch.slug}", else: "/staff"

        {:noreply,
         redirect(socket, to: prefix <> "/statistics?" <> Plug.Conn.Query.encode(query))}

      true ->
        visible_tabs = visible_tabs(socket)

        tab =
          if params["tab"] in visible_tabs,
            do: params["tab"],
            else: if(section, do: List.first(visible_tabs), else: "sales")

        preset =
          if params["period"] in Analytics.presets(),
            do: params["period"],
            else: if(tab == "sales", do: "month", else: "today")

        {period, period_error} =
          if preset == "custom" do
            case Analytics.validate_custom_period(params["from"], params["to"]) do
              {:ok, period} ->
                {period, nil}

              {:error, :invalid_period} ->
                {Analytics.resolve_period("today", nil, nil, branch && branch.id),
                 gettext("Choose a valid period of up to 366 days")}
            end
          else
            {Analytics.resolve_period(preset, nil, nil, branch && branch.id), nil}
          end

        custom_from = if preset == "custom", do: safe_date_param(params["from"]), else: nil
        custom_to = if preset == "custom", do: safe_date_param(params["to"]), else: nil

        comparison_mode = comparison_mode(params["compare"])

        {comparison_period, comparison_error} =
          resolve_comparison(comparison_mode, period, params)

        {heatmap_period, heatmap_error} =
          resolve_heatmap_period(params, if(branch, do: {:branch, branch.id}, else: :network))

        sort = if params["sort"] == "quantity", do: :quantity, else: :revenue

        {:noreply,
         socket
         |> assign(
           tab: tab,
           compare?: comparison_mode != nil and comparison_error == nil and period_error == nil,
           comparison_mode: comparison_mode,
           comparison_period: comparison_period,
           comparison_error: comparison_error,
           comparison_open?: comparison_mode != nil,
           comparison_draft: comparison_mode || "previous",
           comparison_draft_from: safe_date_param(params["compare_from"]),
           comparison_draft_to: safe_date_param(params["compare_to"]),
           comparison_from: safe_date_param(params["compare_from"]),
           comparison_to: safe_date_param(params["compare_to"]),
           page_title:
             cond do
               section -> tab_label(if(section == "comparison", do: "franchise", else: section))
               tab == "sales" -> gettext("Sales")
               true -> gettext("Statistics")
             end,
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
           granularity: granularity(params["granularity"], period),
           granularity_override: valid_granularity(params["granularity"], period),
           visible_tabs: visible_tabs,
           report_tabs: @report_tabs,
           link_options:
             if(tab == "sources" and branch,
               do:
                 Reports.link_options(
                   socket.assigns.current_staff,
                   branch.id,
                   params["link_search"],
                   params["link_id"]
                 ),
               else: []
             ),
           report_filters: report_filters(params),
           heatmap_period: heatmap_period,
           heatmap_error: heatmap_error,
           heatmap_from:
             if(Map.has_key?(params, "heatmap_from"),
               do: safe_date_param(params["heatmap_from"]),
               else: Date.to_iso8601(elem(heatmap_period, 0))
             ),
           heatmap_to:
             if(Map.has_key?(params, "heatmap_to"),
               do: safe_date_param(params["heatmap_to"]),
               else: Date.to_iso8601(elem(heatmap_period, 1))
             ),
           heatmap_fulfillment:
             if(params["fulfillment"] in ~w(all delivery pickup dine_in),
               do: params["fulfillment"],
               else: "all"
             ),
           comparison_metric:
             if(params["metric"] in ~w(revenue orders_per_day avg_check),
               do: params["metric"],
               else: "revenue"
             ),
           heatmap_branch_id:
             if(
               global? and
                 Enum.any?(socket.assigns.staff_branches, &(&1.id == params["heatmap_branch"])),
               do: params["heatmap_branch"],
               else: nil
             ),
           heatmap_detail: nil
         )
         |> then(fn socket ->
           if not is_nil(period_error) or is_nil(tab), do: socket, else: load_tab(socket)
         end)}
    end
  end

  @impl true
  def handle_event("filter", params, socket) do
    query =
      %{
        "tab" => socket.assigns.tab,
        "period" => params["period"] || socket.assigns.preset,
        "sort" => to_string(socket.assigns.sort),
        "compare" => socket.assigns.comparison_mode,
        "compare_from" => socket.assigns.comparison_from,
        "compare_to" => socket.assigns.comparison_to,
        "channel" => params["channel"] || socket.assigns.report_filters["channel"],
        "branch_id" => params["branch_id"] || socket.assigns.report_filters["branch_id"],
        "link_id" => params["link_id"] || socket.assigns.report_filters["link_id"],
        "link_search" => params["link_search"] || socket.assigns.report_filters["link_search"],
        "metric" =>
          if(socket.assigns.comparison_metric != "revenue",
            do: socket.assigns.comparison_metric
          ),
        "heatmap_from" => heatmap_query_value(socket.assigns, :heatmap_from),
        "heatmap_to" => heatmap_query_value(socket.assigns, :heatmap_to),
        "fulfillment" =>
          if(socket.assigns.heatmap_fulfillment != "all",
            do: socket.assigns.heatmap_fulfillment
          ),
        "heatmap_branch" => socket.assigns.heatmap_branch_id
      }
      |> compact_query()
      |> maybe_put_custom(
        Map.put(params, "period", params["period"] || socket.assigns.preset),
        socket.assigns.period
      )

    {:noreply, push_patch(socket, to: statistics_path(socket.assigns, query))}
  end

  def handle_event("heatmap_filter", params, socket) do
    {:noreply,
     push_patch(socket,
       to:
         tab_path(socket.assigns, socket.assigns.tab, %{
           "heatmap_from" => params["heatmap_from"],
           "heatmap_to" => params["heatmap_to"],
           "fulfillment" => params["fulfillment"],
           "heatmap_branch" => params["heatmap_branch"]
         })
     )}
  end

  def handle_event("comparison_metric", %{"metric" => metric}, socket) do
    {:noreply,
     push_patch(socket, to: tab_path(socket.assigns, socket.assigns.tab, %{"metric" => metric}))}
  end

  def handle_event(
        "heatmap_detail",
        %{"day" => day, "hour" => hour},
        %{assigns: %{heatmap: %{period: _}}} = socket
      ) do
    with {day, ""} <- Integer.parse(to_string(day)),
         {hour, ""} <- Integer.parse(to_string(hour)),
         {:ok, detail} <-
           OrderHeatmap.detail(
             socket.assigns.current_staff,
             statistics_scope(socket.assigns),
             socket.assigns.heatmap.period,
             socket.assigns.heatmap_fulfillment,
             day,
             hour,
             socket.assigns.heatmap_branch_id
           ) do
      {:noreply, assign(socket, heatmap_detail: %{day: day, hour: hour, rows: detail})}
    else
      _ -> {:noreply, assign(socket, heatmap_detail: nil)}
    end
  end

  def handle_event("heatmap_detail", _, socket),
    do: {:noreply, assign(socket, heatmap_detail: nil)}

  def handle_event("close_heatmap_detail", _, socket),
    do: {:noreply, assign(socket, heatmap_detail: nil)}

  def handle_event(
        "delivery_day_detail",
        %{"day" => day},
        %{assigns: %{tab: "overview", delivery_quality: _}} = socket
      )
      when is_binary(day) do
    with {:ok, date} <- Date.from_iso8601(day),
         {:ok, detail} <-
           DeliveryQuality.detail(
             socket.assigns.current_staff,
             statistics_scope(socket.assigns),
             socket.assigns.period,
             date
           ) do
      {:noreply, assign(socket, delivery_detail: detail)}
    else
      _ -> {:noreply, assign(socket, delivery_detail: nil)}
    end
  end

  def handle_event("delivery_day_detail", _, socket),
    do: {:noreply, assign(socket, delivery_detail: nil)}

  def handle_event("close_delivery_day_detail", _, socket),
    do: {:noreply, assign(socket, delivery_detail: nil)}

  def handle_event("open_comparison", _, socket),
    do: {:noreply, assign(socket, comparison_open?: true)}

  def handle_event("chart_step", %{"granularity" => value}, socket) do
    {:noreply,
     push_patch(socket,
       to: tab_path(socket.assigns, socket.assigns.tab, %{"granularity" => value})
     )}
  end

  def handle_event("comparison_draft", params, socket) do
    {:noreply,
     assign(socket,
       comparison_draft: comparison_mode(params["compare"]) || "previous",
       comparison_draft_from:
         safe_date_param(params["compare_from"] || socket.assigns.comparison_draft_from),
       comparison_draft_to:
         safe_date_param(params["compare_to"] || socket.assigns.comparison_draft_to)
     )}
  end

  def handle_event("apply_comparison", params, socket) do
    overrides = %{
      "compare" => comparison_mode(params["compare"]) || "previous",
      "compare_from" => safe_date_param(params["compare_from"]),
      "compare_to" => safe_date_param(params["compare_to"])
    }

    {:noreply, push_patch(socket, to: tab_path(socket.assigns, socket.assigns.tab, overrides))}
  end

  def handle_event("close_comparison", _, socket) do
    {:noreply,
     push_patch(socket,
       to:
         tab_path(socket.assigns, socket.assigns.tab, %{
           "compare" => nil,
           "compare_from" => nil,
           "compare_to" => nil
         })
     )}
  end

  def handle_event("refresh_report", _, socket) do
    if socket.assigns.tab in (@report_tabs ++ @base_tabs) and is_nil(socket.assigns.period_error) do
      {:noreply, socket |> assign(refresh_attempts: 0, refresh_retry?: false) |> load_tab()}
    else
      {:noreply, socket}
    end
  end

  defp statistics_scope(assigns),
    do: if(assigns.current_branch, do: {:branch, assigns.current_branch.id}, else: :network)

  defp heatmap_query_value(assigns, key) do
    {from, to} = OrderHeatmap.default_period(statistics_scope(assigns))
    defaults = %{heatmap_from: Date.to_iso8601(from), heatmap_to: Date.to_iso8601(to)}

    if assigns.heatmap_from == defaults.heatmap_from and
         assigns.heatmap_to == defaults.heatmap_to,
       do: nil,
       else: Map.fetch!(assigns, key)
  end

  defp resolve_heatmap_period(params, scope) do
    default = OrderHeatmap.default_period(scope)

    if Map.has_key?(params, "heatmap_from") or Map.has_key?(params, "heatmap_to") do
      with {:ok, from} <- Date.from_iso8601(params["heatmap_from"] || ""),
           {:ok, to} <- Date.from_iso8601(params["heatmap_to"] || ""),
           :ok <- OrderHeatmap.valid_period({from, to}) do
        {{from, to}, nil}
      else
        _ -> {default, gettext("Choose a range of complete Monday–Sunday weeks (up to 52 weeks)")}
      end
    else
      {default, nil}
    end
  end

  defp load_heatmap(socket) do
    scope = statistics_scope(socket.assigns)

    if socket.assigns.heatmap_error do
      assign(socket, heatmap: nil, heatmap_detail: nil)
    else
      case OrderHeatmap.read(
             socket.assigns.current_staff,
             scope,
             socket.assigns.heatmap_period,
             socket.assigns.heatmap_fulfillment,
             socket.assigns.heatmap_branch_id
           ) do
        {:ok, heatmap} -> assign(socket, heatmap: heatmap, heatmap_detail: nil)
        {:error, _} -> assign(socket, heatmap: nil, heatmap_detail: nil)
      end
    end
  end

  @impl true
  def handle_info(:analytics_visibility_changed, socket) do
    tabs = visible_tabs(socket)
    socket = assign(socket, visible_tabs: tabs)

    cond do
      socket.assigns.section && tabs == [] ->
        {:noreply, push_navigate(socket, to: overview_path(socket.assigns))}

      socket.assigns.tab in ~w(orders cancelled refunds) and
          not Identity.can?(socket.assigns.current_staff, "orders.read") ->
        {:noreply, push_navigate(socket, to: overview_path(socket.assigns))}

      is_nil(socket.assigns.period_error) ->
        {:noreply, load_tab(socket)}

      true ->
        {:noreply, socket}
    end
  end

  def handle_info({:refresh_report, epoch}, socket) do
    if epoch == socket.assigns.refresh_epoch and
         socket.assigns.tab in (@report_tabs ++ @base_tabs) and
         is_nil(socket.assigns.period_error) do
      {:noreply,
       socket
       |> assign(refresh_attempts: socket.assigns.refresh_attempts + 1)
       |> refresh_relative_period()
       |> load_tab()}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_, socket), do: {:noreply, socket}

  defp refresh_relative_period(%{assigns: %{preset: "custom"}} = socket), do: socket

  defp refresh_relative_period(socket) do
    period =
      Analytics.resolve_period(
        socket.assigns.preset,
        nil,
        nil,
        socket.assigns.current_branch && socket.assigns.current_branch.id
      )

    {comparison_period, comparison_error} =
      resolve_comparison(socket.assigns.comparison_mode, period, %{
        "compare_from" => socket.assigns.comparison_from,
        "compare_to" => socket.assigns.comparison_to
      })

    assign(socket,
      period: period,
      granularity: granularity(socket.assigns.granularity_override, period),
      granularity_override: valid_granularity(socket.assigns.granularity_override, period),
      comparison_period: comparison_period,
      comparison_error: comparison_error,
      compare?: socket.assigns.comparison_mode != nil and comparison_error == nil
    )
  end

  defp cancel_report_refresh(socket) do
    if socket.assigns[:refresh_timer], do: Process.cancel_timer(socket.assigns.refresh_timer)
    assign(socket, refresh_timer: nil)
  end

  defp schedule_report_refresh(socket) do
    socket = cancel_report_refresh(socket)

    pending? =
      (socket.assigns.tab in @report_tabs and
         Map.get(socket.assigns.report, :refresh_pending, false)) or
        ((socket.assigns.tab in ~w(overview sales) and socket.assigns[:overview]) &&
           (socket.assigns.overview.state == :partial or
              match?(%{state: :partial}, socket.assigns.overview.comparison)))

    socket = if pending?, do: socket, else: assign(socket, refresh_attempts: 0)
    exhausted? = pending? and socket.assigns.refresh_attempts >= 5

    today =
      Analytics.resolve_period(
        "today",
        nil,
        nil,
        socket.assigns.current_branch && socket.assigns.current_branch.id
      )
      |> elem(0)

    current? =
      Date.compare(elem(socket.assigns.period, 0), today) != :gt and
        Date.compare(elem(socket.assigns.period, 1), today) != :lt

    delay =
      cond do
        exhausted? and current? -> 30_000
        exhausted? -> nil
        pending? -> 2_000
        current? -> 30_000
        true -> nil
      end

    timer =
      if connected?(socket) and delay,
        do: Process.send_after(self(), {:refresh_report, socket.assigns.refresh_epoch}, delay)

    assign(socket, refresh_timer: timer, refresh_retry?: exhausted?)
  end

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns[:refresh_timer], do: Process.cancel_timer(socket.assigns.refresh_timer)
    :ok
  end

  defp comparison_mode(mode) when mode in ["true", "previous"], do: "previous"
  defp comparison_mode(mode) when mode in ["year", "custom"], do: mode
  defp comparison_mode(_), do: nil

  defp resolve_comparison(nil, _, _), do: {nil, nil}

  defp resolve_comparison(mode, {from, to} = period, params) do
    dates =
      case mode do
        "previous" -> Analytics.previous_period(period)
        "year" -> {Date.shift(from, year: -1), Date.shift(to, year: -1)}
        "custom" -> {params["compare_from"], params["compare_to"]}
      end

    {from, to} = dates
    from = if is_struct(from, Date), do: Date.to_iso8601(from), else: from
    to = if is_struct(to, Date), do: Date.to_iso8601(to), else: to

    case Analytics.validate_custom_period(from, to) do
      {:ok, value} -> {value, nil}
      _ -> {nil, gettext("Choose a valid comparison period of up to 366 days")}
    end
  end

  defp maybe_put_custom(query, %{"period" => "custom"} = params, {from, to}) do
    query
    |> Map.put("from", params |> Map.get("from", Date.to_iso8601(from)) |> safe_date_param())
    |> Map.put("to", params |> Map.get("to", Date.to_iso8601(to)) |> safe_date_param())
  end

  defp maybe_put_custom(query, _params, _period), do: query

  defp compact_query(query),
    do:
      Map.reject(query, fn {key, value} ->
        value in [nil, ""] or (key == "compare" and value == "false")
      end)

  defp safe_date_param(value) when is_binary(value) do
    if Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, value), do: value, else: ""
  end

  defp safe_date_param(_value), do: ""

  defp load_tab(%{assigns: %{tab: "overview"}} = socket) do
    assigns = socket.assigns
    scope = if(assigns.current_branch, do: {:branch, assigns.current_branch.id}, else: :network)

    opts =
      if assigns.compare? and assigns.comparison_period,
        do: [comparison_period: assigns.comparison_period],
        else: []

    with {:ok, overview} <- Overview.read(assigns.current_staff, scope, assigns.period, opts),
         {:ok, delivery_quality} <-
           DeliveryQuality.read(assigns.current_staff, scope, assigns.period) do
      socket
      |> assign(overview: overview, delivery_quality: delivery_quality, delivery_detail: nil)
      |> load_heatmap()
      |> schedule_report_refresh()
    else
      {:error, _} -> put_flash(socket, :error, gettext("Statistics are unavailable"))
    end
  end

  defp load_tab(%{assigns: %{tab: tab}} = socket) when tab in ~w(orders cancelled refunds) do
    assigns = socket.assigns
    scope = if(assigns.current_branch, do: {:branch, assigns.current_branch.id}, else: :network)
    kind = %{"orders" => :completed, "cancelled" => :cancelled, "refunds" => :refunds}[tab]

    page =
      case Integer.parse(assigns.report_filters["page"] || "1") do
        {n, ""} when n in 1..10_000 -> n
        _ -> 1
      end

    case Overview.orders(assigns.current_staff, scope, assigns.period, kind, page: page) do
      {:ok, result} ->
        assign(socket, order_drilldown: result)

      {:error, _} ->
        assign(socket, order_drilldown: %{rows: [], page: 1, pages: 1, total_rows: 0})
    end
  end

  defp load_tab(%{assigns: %{tab: "sales"}} = socket) do
    assigns = socket.assigns
    scope = if(assigns.current_branch, do: {:branch, assigns.current_branch.id}, else: :network)

    opts =
      if assigns.compare? and assigns.comparison_period,
        do: [comparison_period: assigns.comparison_period],
        else: []

    with {:ok, overview} <- Overview.read(assigns.current_staff, scope, assigns.period, opts),
         {:ok, fulfillment} <-
           Overview.details(assigns.current_staff, scope, assigns.period, :fulfillment),
         {:ok, payment} <-
           Overview.details(assigns.current_staff, scope, assigns.period, :payment),
         {:ok, sources} <- Overview.details(assigns.current_staff, scope, assigns.period, :source),
         {:ok, destinations} <-
           Overview.details(assigns.current_staff, scope, assigns.period, :destination),
         {:ok, products} <-
           Overview.details(assigns.current_staff, scope, assigns.period, :products),
         {:ok, categories} <-
           Overview.details(assigns.current_staff, scope, assigns.period, :categories) do
      assign(socket,
        overview: overview,
        by_fulfillment: fulfillment,
        by_payment: payment,
        by_source: sources,
        by_destination: destinations,
        top_products: Enum.take(sort_details(products, :revenue), 5),
        top_categories: Enum.take(categories, 5)
      )
      |> schedule_report_refresh()
    else
      _ -> put_flash(socket, :error, gettext("Statistics are unavailable"))
    end
  end

  defp load_tab(%{assigns: %{tab: "products"}} = socket) do
    assigns = socket.assigns
    scope = if(assigns.current_branch, do: {:branch, assigns.current_branch.id}, else: :network)
    {:ok, products} = Overview.details(assigns.current_staff, scope, assigns.period, :products)
    assign(socket, products: sort_details(products, assigns.sort)) |> schedule_report_refresh()
  end

  defp load_tab(%{assigns: %{tab: "categories"}} = socket) do
    assigns = socket.assigns
    scope = if(assigns.current_branch, do: {:branch, assigns.current_branch.id}, else: :network)

    {:ok, categories} =
      Overview.details(assigns.current_staff, scope, assigns.period, :categories)

    assign(socket, categories: categories) |> schedule_report_refresh()
  end

  defp load_tab(%{assigns: %{tab: tab}} = socket) when tab in @report_tabs do
    if tab == "franchise" do
      case Reports.read(
             socket.assigns.current_staff,
             :franchise,
             socket.assigns.period,
             "franchise",
             socket.assigns.report_filters
           ) do
        {:ok, report} ->
          branches = socket.assigns.staff_branches

          rows =
            Enum.map(report.branch_rows, fn row ->
              branch = Enum.find(branches, &(&1.id == row.branch_id))
              Map.put(row, :name, if(branch, do: branch.name, else: row.branch_id))
            end)

          rows =
            BranchComparison.rows(rows, socket.assigns.period, socket.assigns.comparison_metric)

          socket
          |> assign(report: report, report_previous: nil, comparison_rows: rows)
          |> schedule_report_refresh()

        {:error, _} ->
          push_navigate(socket, to: overview_path(socket.assigns))
      end
    else
      load_collected_report(socket, tab)
    end
  end

  defp load_collected_report(socket, tab) do
    scope =
      cond do
        tab == "franchise" -> :franchise
        socket.assigns.current_branch -> {:branch, socket.assigns.current_branch.id}
        true -> :network
      end

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

        socket |> assign(report: report, report_previous: previous) |> schedule_report_refresh()

      {:error, reason} when reason in [:hidden_filter, :forbidden] ->
        push_navigate(socket, to: overview_path(socket.assigns))

      _ ->
        assign(socket,
          report: unavailable_report(),
          report_previous: nil
        )
    end
  end

  defp sort_details(rows, :quantity), do: Enum.sort_by(rows, &{-&1.quantity, -&1.revenue})
  defp sort_details(rows, _), do: Enum.sort_by(rows, &{-&1.revenue, -&1.quantity})

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
      partial_days: 0,
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
    branch = socket.assigns.current_branch
    staff = socket.assigns.current_staff

    tabs =
      case socket.assigns.section do
        nil -> @base_tabs
        "comparison" -> ["franchise"]
        section when section in ~w(channels sources funnel customers) -> [section]
        _ -> []
      end

    Enum.filter(tabs, fn tab ->
      cond do
        tab in ~w(orders cancelled refunds) ->
          Identity.can?(staff, "orders.read")

        tab in @base_tabs ->
          true

        tab == "franchise" ->
          Identity.can?(staff, "statistics.network") and is_nil(branch) and
            Features.enabled?("analytics_franchise", :franchise)

        branch ->
          Features.enabled?(Reports.feature_for_tab(tab), {:branch, branch.id})

        true ->
          Enum.any?(
            socket.assigns.staff_branches,
            &Features.enabled?(Reports.feature_for_tab(tab), {:branch, &1.id})
          )
      end
    end)
  end

  defp report_available?(assigns, tab) do
    feature = Reports.feature_for_tab(tab)

    if assigns.current_branch do
      Features.enabled?(feature, {:branch, assigns.current_branch.id})
    else
      ids = Enum.map(assigns.staff_branches, & &1.id)
      MapSet.size(Features.enabled_branches(feature, ids)) > 0
    end
  end

  defp sanitize_branch_filter(params) do
    case Map.fetch(params, "branch_id") do
      :error -> params
      {:ok, value} when is_binary(value) -> params
      _ -> Map.put(params, "branch_id", "invalid-branch")
    end
  end

  defp report_filters(params),
    do: Map.take(params, ["channel", "link_id", "link_search", "branch_ids", "branch_id", "page"])

  defp channel_options(assigns) do
    ids =
      if assigns.current_branch,
        do: [assigns.current_branch.id],
        else: Enum.map(assigns.staff_branches, & &1.id)

    ids
    |> Overview.allowed_sources()
    |> Map.values()
    |> List.flatten()
    |> Kernel.++(["other"])
    |> Enum.uniq()
    |> Enum.map(fn key -> {source_label(key), key} end)
  end

  defp tab_path(assigns, tab, overrides \\ %{}) do
    {from, to} = assigns.period

    query =
      %{
        "tab" => tab,
        "period" => assigns.preset,
        "sort" => to_string(assigns.sort),
        "granularity" => assigns.granularity_override,
        "compare" => assigns.comparison_mode,
        "compare_from" => assigns.comparison_from,
        "compare_to" => assigns.comparison_to,
        "channel" => assigns.report_filters["channel"],
        "branch_id" => assigns.report_filters["branch_id"],
        "branch_ids" => assigns.report_filters["branch_ids"],
        "link_id" => assigns.report_filters["link_id"],
        "link_search" => assigns.report_filters["link_search"],
        "heatmap_from" => heatmap_query_value(assigns, :heatmap_from),
        "heatmap_to" => heatmap_query_value(assigns, :heatmap_to),
        "fulfillment" =>
          if(assigns[:heatmap_fulfillment] != "all", do: assigns[:heatmap_fulfillment]),
        "heatmap_branch" => assigns[:heatmap_branch_id],
        "metric" => if(assigns[:comparison_metric] != "revenue", do: assigns[:comparison_metric])
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

    statistics_path(assigns, compact_query(query))
  end

  defp statistics_path(assigns, query) do
    prefix =
      if assigns.current_branch, do: "/staff/b/#{assigns.current_branch.slug}", else: "/staff"

    route = if assigns.section, do: "/analytics/#{assigns.section}", else: "/statistics"
    prefix <> route <> "?" <> Plug.Conn.Query.encode(query)
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

  defp format_updated(nil, _zone), do: "—"

  defp format_updated(%DateTime{} = at, zone) do
    local =
      case DateTime.shift_zone(at, zone) do
        {:ok, value} -> value
        _ -> at
      end

    "#{Calendar.strftime(local, "%d.%m.%Y %H:%M")} #{local.time_zone}"
  end

  defp percent(nil), do: "—"
  defp percent(value), do: "#{value}%"

  defp scalar_query(params),
    do: params |> Enum.filter(fn {_key, value} -> is_binary(value) end) |> Map.new()

  defp display_count(nil), do: "—"
  defp display_count(value), do: value

  defp comparison_delta(
         %{state: :ready, comparison: %{state: :ready, summary: previous}, summary: current},
         key
       ),
       do: delta(Map.fetch!(current, key), Map.fetch!(previous, key))

  defp comparison_delta(_, _), do: nil

  defp available_granularities({from, to}) do
    case Date.diff(to, from) + 1 do
      days when days <= 7 -> ~w(day)
      days when days <= 31 -> ~w(day week)
      _ -> ~w(day week month)
    end
  end

  defp valid_granularity(value, period),
    do: if(value in available_granularities(period), do: value, else: nil)

  defp granularity(value, {from, to} = period) do
    valid_granularity(value, period) ||
      case Date.diff(to, from) + 1 do
        days when days <= 31 -> "day"
        days when days <= 90 -> "week"
        _ -> "month"
      end
  end

  defp period_query(assigns) do
    {from, to} = assigns.period

    %{
      "period" => assigns.preset,
      "compare" => assigns.comparison_mode,
      "compare_from" => assigns.comparison_from,
      "compare_to" => assigns.comparison_to
    }
    |> then(fn query ->
      if assigns.preset == "custom",
        do: Map.merge(query, %{"from" => Date.to_iso8601(from), "to" => Date.to_iso8601(to)}),
        else: query
    end)
    |> compact_query()
  end

  defp branch_overview_path(assigns, id) do
    branch = Enum.find(assigns.staff_branches, &(&1.id == id))
    "/staff/b/#{branch.slug}/statistics?" <> Plug.Conn.Query.encode(period_query(assigns))
  end

  defp drilldown_path(assigns, tab),
    do: statistics_path(assigns, Map.put(period_query(assigns), "tab", tab))

  defp overview_path(assigns) do
    prefix =
      if(assigns.current_branch, do: "/staff/b/#{assigns.current_branch.slug}", else: "/staff")

    prefix <> "/statistics?" <> Plug.Conn.Query.encode(period_query(assigns))
  end

  defp order_path(assigns, row) do
    branch = Enum.find(assigns.staff_branches, &(&1.id == row.branch_id))
    "/staff/b/#{branch.slug}/orders/#{row.id}"
  end

  defp report_path(assigns, "comparison"),
    do: "/staff/analytics/comparison?" <> Plug.Conn.Query.encode(period_query(assigns))

  defp report_path(assigns, report) do
    prefix =
      if(assigns.current_branch, do: "/staff/b/#{assigns.current_branch.slug}", else: "/staff")

    prefix <> "/analytics/#{report}?" <> Plug.Conn.Query.encode(period_query(assigns))
  end

  defp fulfillment_label("other"), do: gettext("Other")
  defp fulfillment_label(key), do: OrderHelpers.fulfillment_label(key)
  defp payment_label(key), do: OrderHelpers.payment_label(key)

  defp source_label("app"), do: gettext("Storefront")
  defp source_label("staff"), do: gettext("Admin")
  defp source_label("pos"), do: gettext("POS")
  defp source_label("other"), do: gettext("Other")
  defp source_label(key), do: Channels.name(key)

  defp destination_label("own"), do: gettext("Without CRM transfer")
  defp destination_label("other"), do: gettext("Other")

  defp destination_label(key) do
    case Delivest.Integrations.Crm.provider_name(key) do
      name when is_binary(name) -> name
      _ -> key
    end
  end

  def staff_page_header(assigns) do
    ~H"""
    <div
      id="staff-page-header"
      class="mb-3 flex min-w-0 flex-col gap-3 lg:flex-row lg:items-center lg:justify-between"
    >
      <div class="min-w-0 shrink-0">
        <div class="relative flex items-center gap-2">
          <h1 class="text-2xl font-semibold leading-tight">{@page_title}</h1>
          <details :if={@section} id="statistics-report-description">
            <summary
              aria-label={gettext("Report description")}
              title={gettext("Report description")}
              class="flex cursor-pointer list-none items-center text-base-content/50 hover:text-base-content"
            >
              <.icon name="hero-information-circle" class="size-4" />
            </summary>
            <p class="absolute left-0 top-full z-20 mt-2 w-72 max-w-[80vw] rounded-xl border border-base-300 bg-base-100 p-3 text-sm leading-relaxed shadow-lg">
              {report_description(@tab)}
            </p>
          </details>
        </div>
        <p :if={is_nil(@period_error)} class="mt-1 text-xs text-base-content/60">
          {if(@current_branch, do: @current_branch.name, else: gettext("All branches"))} · {format_period(
            @period
          )}
        </p>
        <p
          :if={@tab in ~w(overview sales) and is_nil(@period_error) and assigns[:overview]}
          class="text-xs text-base-content/60"
        >
          {gettext("Updated at %{time}",
            time: format_updated(@overview.updated_at, @overview.timezone)
          )}
        </p>
      </div>
      <div class="flex min-w-0 flex-wrap items-center gap-2 lg:ml-auto lg:justify-end">
        <.form
          for={@form}
          id="statistics-filter"
          phx-change="filter"
          class="flex min-w-0 flex-wrap items-center gap-2 [&>fieldset]:mb-0 [&>fieldset]:w-auto"
        >
          <label for="statistics-period" class="text-xs text-base-content/70">{gettext("Period")}</label>
          <select
            id="statistics-period"
            name="period"
            aria-label={gettext("Period")}
            class="select select-sm w-40"
          >
            <option :for={preset <- Analytics.presets()} value={preset} selected={preset == @preset}>
              {preset_label(preset)}
            </option>
          </select>
          <%= if @preset == "custom" do %>
            <input
              type="date"
              name="from"
              value={@custom_from}
              class="input input-sm w-36"
            />
            <input
              type="date"
              name="to"
              value={@custom_to}
              class="input input-sm w-36"
            />
          <% end %>
          <.input
            :if={@tab in ~w(channels comparison franchise)}
            field={@form[:channel]}
            type="select"
            prompt={gettext("All channels")}
            options={channel_options(assigns)}
            class="select select-sm w-36"
          />
          <.input
            :if={@tab == "sources"}
            field={@form[:link_search]}
            type="text"
            placeholder={gettext("Find advertising link")}
            class="input input-sm w-40"
          />
          <.input
            :if={@tab == "sources"}
            field={@form[:link_id]}
            type="select"
            prompt={gettext("All advertising links")}
            options={@link_options}
            class="select select-sm w-48"
          />
        </.form>
        <.form
          :if={@tab == "sales" and length(available_granularities(@period)) > 1}
          for={to_form(%{})}
          id="statistics-chart-step-form"
          phx-change="chart_step"
          class="flex items-center gap-2"
        >
          <label for="statistics-granularity" class="text-xs text-base-content/70">{gettext(
            "Chart grouping"
          )}</label>
          <select
            id="statistics-granularity"
            name="granularity"
            aria-label={gettext("Chart grouping")}
            class="select select-bordered select-sm w-36"
          >
            <option value="day" selected={@granularity == "day"}>{gettext("By day")}</option>
            <option value="week" selected={@granularity == "week"}>{gettext("By week")}</option>
            <option
              :if={"month" in available_granularities(@period)}
              value="month"
              selected={@granularity == "month"}
            >
              {gettext("By month")}
            </option>
          </select>
        </.form>
        <button
          :if={@tab in ~w(overview sales)}
          id="statistics-compare"
          type="button"
          phx-click="open_comparison"
          class="btn btn-sm btn-outline"
        >{gettext("Compare periods")}</button>
      </div>
    </div>
    """
  end

  def staff_page_navigation(_assigns), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <div class="statistics-surface space-y-4">
      <nav
        :if={@section in ~w(sources funnel)}
        id="sources-advertising-tabs"
        class="tabs tabs-box tabs-sm max-w-full flex-nowrap overflow-x-auto"
      >
        <.link
          :if={report_available?(assigns, "sources")}
          navigate={report_path(assigns, "sources")}
          class={["tab", @section == "sources" && "tab-active"]}
          aria-current={@section == "sources" && "page"}
        >{gettext("Sources")}</.link>
        <.link
          :if={report_available?(assigns, "funnel")}
          navigate={report_path(assigns, "funnel")}
          class={["tab", @section == "funnel" && "tab-active"]}
          aria-current={@section == "funnel" && "page"}
        >{gettext("Order funnel")}</.link>
        <.link
          :if={
            Identity.can?(@current_staff, "statistics.network") and
              Features.enabled?("yandex_costs", :franchise)
          }
          navigate={"/staff/analytics/advertising?" <> URI.encode_query(%{"period" => @preset, "from" => elem(@period, 0), "to" => elem(@period, 1)})}
          class="tab"
        >{gettext("Campaigns")}</.link>
      </nav>
      <section
        :if={@tab in ~w(overview sales) and @comparison_open?}
        id="statistics-comparison-controls"
        class="rounded-xl border border-base-300 p-3 space-y-2"
      >
        <.form
          for={to_form(%{})}
          id="statistics-comparison-form"
          phx-change="comparison_draft"
          phx-submit="apply_comparison"
          class="flex flex-wrap items-end gap-2 [&>fieldset]:mb-0 [&>fieldset]:w-auto [&_input]:w-40 [&_input]:input-sm [&_select]:w-60 [&_select]:select-sm [&_.label-text]:text-xs"
        >
          <.input
            id="statistics-comparison-mode"
            name="compare"
            type="select"
            value={@comparison_draft}
            label={gettext("Comparison period")}
            options={[
              {gettext("Previous equivalent period"), "previous"},
              {gettext("Same period last year"), "year"},
              {gettext("Custom dates"), "custom"}
            ]}
          />
          <.input
            :if={@comparison_draft == "custom"}
            id="statistics-comparison-from"
            name="compare_from"
            type="date"
            value={@comparison_draft_from}
            label={gettext("Comparison start date")}
          />
          <.input
            :if={@comparison_draft == "custom"}
            id="statistics-comparison-to"
            name="compare_to"
            type="date"
            value={@comparison_draft_to}
            label={gettext("Comparison end date")}
          />
          <div class="flex flex-wrap items-center gap-2 pb-0.5">
            <button type="submit" class="btn btn-sm btn-primary">{gettext("Apply comparison")}</button>
            <button
              id="statistics-close-comparison"
              type="button"
              phx-click="close_comparison"
              class="btn btn-sm btn-ghost"
            >{gettext("Close comparison")}</button>
          </div>
        </.form>
        <p
          :if={@comparison_error}
          id="statistics-comparison-error"
          role="alert"
          class="text-sm text-error"
        >
          {@comparison_error}
        </p>
        <div
          :if={@compare?}
          id="statistics-comparison-periods"
          class="flex flex-wrap gap-x-5 gap-y-1 text-xs text-base-content/70"
        >
          <p>{gettext("Selected period")}: <strong>{format_period(@period)}</strong></p>
          <p>{gettext("Comparison period")}: <strong>{format_period(@comparison_period)}</strong></p>
        </div>
      </section>

      <p :if={is_nil(@tab)} id="statistics-choose-branch" class="alert">
        {gettext("Choose a branch to view statistics.")}
      </p>

      <p :if={@period_error} id="statistics-period-error" role="alert" class="text-sm text-error">
        {@period_error}
      </p>

      <section
        :if={@tab == "overview" and is_nil(@period_error) and assigns[:overview]}
        id="statistics-overview"
        class="space-y-5"
      >
        <p
          :if={@overview.state == :empty}
          id="statistics-no-data"
          class="rounded-box border border-base-300 bg-base-100 p-4 text-sm text-base-content/70"
        >
          {gettext("No completed orders in this period")}
        </p>
        <p
          :if={@overview.state == :partial}
          id="statistics-partial"
          class="rounded-box border border-warning/50 bg-warning/10 p-4 text-sm"
        >
          {gettext("Some daily totals are updating. The latest published figures are shown.")}
        </p>
        <button
          :if={@refresh_retry?}
          id="statistics-overview-retry"
          type="button"
          phx-click="refresh_report"
          class="btn btn-sm btn-outline"
        >{gettext("Try again")}</button>
        <p class="text-xs text-base-content/60">
          {gettext(
            "Completed orders by local creation date. Successful refunds reduce sales for the original order date."
          )}
        </p>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <.link
            id="statistics-sales-link"
            patch={tab_path(assigns, "sales")}
            class="block rounded-box focus-visible:outline-2 focus-visible:outline-primary"
          >
            <.stat_card
              icon="hero-banknotes"
              label={gettext("Sales after refunds")}
              delta={comparison_delta(@overview, :revenue)}
            >
              {OrderHelpers.money(@overview.summary.revenue)}
            </.stat_card>
          </.link>
          <.link
            :if={Identity.can?(@current_staff, "orders.read")}
            id="statistics-orders-link"
            patch={drilldown_path(assigns, "orders")}
            class="block rounded-box focus-visible:outline-2 focus-visible:outline-primary"
          >
            <.stat_card
              icon="hero-shopping-bag"
              label={gettext("Completed orders")}
              delta={comparison_delta(@overview, :orders_count)}
            >
              {@overview.summary.orders_count}
            </.stat_card>
          </.link>
          <div :if={!Identity.can?(@current_staff, "orders.read")}>
            <.stat_card
              icon="hero-shopping-bag"
              label={gettext("Completed orders")}
              delta={comparison_delta(@overview, :orders_count)}
            >
              {@overview.summary.orders_count}
            </.stat_card>
          </div>
          <.link
            id="statistics-average-link"
            patch={tab_path(assigns, "sales")}
            class="block rounded-box focus-visible:outline-2 focus-visible:outline-primary"
          >
            <.stat_card
              icon="hero-receipt-percent"
              label={gettext("Average check")}
              delta={comparison_delta(@overview, :avg_check)}
            >
              {OrderHelpers.money(@overview.summary.avg_check)}
            </.stat_card>
          </.link>
        </div>
        <.heatmap_panel
          :if={assigns[:heatmap] || @heatmap_error}
          heatmap={@heatmap || %{cells: [], branches: [], period: @heatmap_period, state: :empty}}
          detail={@heatmap_detail}
          from={@heatmap_from}
          to={@heatmap_to}
          error={@heatmap_error}
          fulfillment={@heatmap_fulfillment}
          branch_id={@heatmap_branch_id}
          network?={@global_statistics?}
        />
        <p
          :if={
            (@compare? and @overview.comparison) && @overview.comparison.state == :ready &&
              @overview.comparison.summary.orders_count == 0
          }
          class="text-sm text-base-content/60"
        >
          {gettext("The comparison period has no completed orders; percentage change is unavailable.")}
        </p>
        <p
          :if={(@compare? and @overview.comparison) && @overview.comparison.state == :partial}
          id="statistics-overview-comparison-partial"
          class="text-sm text-warning"
        >
          {gettext("Some daily totals are updating. The latest published figures are shown.")}
        </p>
        <.card class="p-4">
          <.chart
            id="statistics-overview-sales"
            title={gettext("Sales over time")}
            compact
            daily={@overview.daily}
            comparison={
              if(@compare? && @overview.comparison && @overview.comparison.state == :ready,
                do: @overview.comparison
              )
            }
            granularity="day"
            metric={:revenue}
          />
        </.card>
        <div class="grid gap-3 md:grid-cols-2">
          <section id="statistics-clients" class="rounded-box border border-base-300 bg-base-100 p-4">
            <h2 class="font-semibold">{gettext("Customers")}</h2>
            <p class="mt-2 text-sm">
              {gettext("New")}: <strong>{display_count(@overview.clients.new)}</strong>
              · {gettext("Returning")}: <strong>{display_count(@overview.clients.returning)}</strong>
            </p>
            <p class="mt-1 text-xs text-base-content/60">
              {gettext("Identified orders")}: {display_count(@overview.clients.identified_orders)}/{display_count(
                @overview.clients.total_orders
              )} ({percent(@overview.clients.coverage)})
            </p>
          </section>
          <section id="statistics-quality" class="rounded-box border border-base-300 bg-base-100 p-4">
            <h2 class="font-semibold">{gettext("Service quality")}</h2>
            <p class="mt-2 text-sm">
              {gettext("Cancellations")}: <strong>{@overview.summary.cancelled_count}</strong>
              · {gettext("Cancellation rate")}:
              <strong>{percent(@overview.summary.cancellation_rate)}</strong>
            </p>
            <p class="mt-1 text-sm">
              {gettext("Refunds")}:
              <strong>{OrderHelpers.money(@overview.summary.refund_amount)}</strong>
            </p>
            <div
              :if={Identity.can?(@current_staff, "orders.read")}
              class="mt-2 flex flex-wrap gap-3 text-xs"
            >
              <.link
                id="statistics-cancelled-link"
                patch={drilldown_path(assigns, "cancelled")}
                class="link link-primary"
              >{gettext("Cancellation details")}</.link>
              <.link
                id="statistics-refunds-link"
                patch={drilldown_path(assigns, "refunds")}
                class="link link-primary"
              >{gettext("Refund details")}</.link>
            </div>
            <p class="mt-1 text-xs text-base-content/60">
              {gettext("Cancellation rate uses completed plus cancelled orders as its denominator.")}
            </p>
          </section>
        </div>
        <.delivery_quality_panel quality={@delivery_quality} detail={@delivery_detail} />
        <section
          :if={@global_statistics?}
          id="statistics-branch-summary"
          class="rounded-box border border-base-300 bg-base-100 p-4 overflow-x-auto"
        >
          <h2 class="font-semibold mb-3">{gettext("Branches")}</h2>
          <.table
            id="statistics-overview-branches"
            rows={@overview.branches}
            row_id={fn branch -> "statistics-overview-branch-#{branch.id}" end}
          >
            <:col :let={branch} key="branch" label={gettext("Branch")}>{branch.name}</:col>
            <:col :let={branch} key="revenue" label={gettext("Sales after refunds")} numeric>
              {OrderHelpers.money(branch.revenue)}
            </:col>
            <:col :let={branch} key="orders" label={gettext("Completed orders")} numeric>
              {branch.orders_count}
            </:col>
            <:col :let={branch} key="average" label={gettext("Average check")} numeric>
              {OrderHelpers.money(branch.avg_check)}
            </:col>
            <:col :let={branch} key="cancelled" label={gettext("Cancellation rate")} numeric>
              {percent(branch.cancellation_rate)}
            </:col>
            <:action :let={branch}>
              <.link navigate={branch_overview_path(assigns, branch.id)} class="link link-primary">{gettext(
                "View branch"
              )}</.link>
            </:action>
          </.table>
        </section>
      </section>

      <section
        :if={@tab in ~w(orders cancelled refunds) and is_nil(@period_error)}
        id="statistics-order-details"
        class="space-y-4"
      >
        <.link patch={drilldown_path(assigns, "overview")} class="btn btn-sm btn-ghost">{gettext(
          "Back to statistics"
        )}</.link>
        <h2 class="text-xl font-semibold">{tab_label(@tab)}</h2>
        <p
          :if={@order_drilldown.total_rows == 0}
          class="rounded-box border border-base-300 bg-base-100 p-4 text-sm text-base-content/60"
        >
          {gettext("No orders in this period")}
        </p>
        <.table
          id="statistics-order-rows"
          rows={@order_drilldown.rows}
          row_id={fn row -> "statistics-order-#{row.id}" end}
        >
          <:col :let={row} key="number" label={gettext("Order")}>
            <.link navigate={order_path(assigns, row)} class="link link-primary">#{row.number}</.link>
          </:col>
          <:col :let={row} key="branch" label={gettext("Branch")}>{row.branch_name}</:col>
          <:col :let={row} key="amount" label={gettext("Amount")} numeric>
            {OrderHelpers.money(row.total_amount)}
          </:col>
          <:col :let={row} key="refund" label={gettext("Refunds")} numeric>
            {OrderHelpers.money(row.refund_amount)}
          </:col>
          <:col :let={row} key="reason" label={gettext("Reason")}>{row.reason || "—"}</:col>
        </.table>
        <nav
          :if={@order_drilldown.pages > 1}
          aria-label={gettext("Pages")}
          class="flex items-center gap-3"
        >
          <.link
            :if={@order_drilldown.page > 1}
            patch={tab_path(assigns, @tab, %{"page" => to_string(@order_drilldown.page - 1)})}
            class="btn btn-sm btn-outline"
          >{gettext("Previous")}</.link>
          <span class="text-sm">{@order_drilldown.page}/{@order_drilldown.pages}</span>
          <.link
            :if={@order_drilldown.page < @order_drilldown.pages}
            patch={tab_path(assigns, @tab, %{"page" => to_string(@order_drilldown.page + 1)})}
            class="btn btn-sm btn-outline"
          >{gettext("Next")}</.link>
        </nav>
      </section>

      <.report_panel
        :if={@tab in @report_tabs and is_nil(@period_error)}
        tab={@tab}
        title={tab_label(@tab)}
        show_title={is_nil(@section)}
        report={@report}
        report_previous={@report_previous}
        refresh_retry?={@refresh_retry?}
        current_staff={@current_staff}
        current_branch={@current_branch}
        staff_branches={@staff_branches}
        ranking_rows={assigns[:comparison_rows] || []}
        ranking_metric={@comparison_metric}
        period={@period}
        branch_path={fn id -> branch_overview_path(assigns, id) end}
        page_path={fn page -> tab_path(assigns, @tab, %{"page" => Integer.to_string(page)}) end}
      />

      <section
        :if={@tab == "sales" and is_nil(@period_error)}
        id="statistics-sales-detail"
        class="space-y-4"
      >
        <.link
          id="statistics-heatmap-link"
          href={tab_path(assigns, "overview") <> "#statistics-heatmap"}
          class="btn btn-sm btn-outline"
        >{gettext("When orders arrive")}</.link>
        <p
          :if={@overview.state == :partial}
          id="statistics-partial"
          class="rounded-box border border-warning/50 bg-warning/10 p-4 text-sm"
        >
          {gettext("Some daily totals are updating. The latest published figures are shown.")}
        </p>
        <p
          :if={@overview.state == :empty}
          id="statistics-no-data"
          class="rounded-box border border-base-300 bg-base-100 p-4 text-sm"
        >
          {gettext("No completed orders in this period")}
        </p>
        <button
          :if={@refresh_retry?}
          id="statistics-sales-retry"
          type="button"
          phx-click="refresh_report"
          class="btn btn-sm btn-outline"
        >{gettext("Try again")}</button>
        <p class="text-sm text-base-content/70">
          {gettext(
            "Completed orders by local creation date. Successful refunds reduce sales for the original order date."
          )}
        </p>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <.stat_card
            icon="hero-banknotes"
            label={gettext("Sales after refunds")}
            delta={comparison_delta(@overview, :revenue)}
          >
            {OrderHelpers.money(@overview.summary.revenue)}
          </.stat_card>
          <.stat_card
            icon="hero-shopping-bag"
            label={gettext("Orders")}
            delta={comparison_delta(@overview, :orders_count)}
          >
            {@overview.summary.orders_count}
          </.stat_card>
          <.stat_card
            icon="hero-receipt-percent"
            label={gettext("Average check")}
            delta={comparison_delta(@overview, :avg_check)}
          >
            {OrderHelpers.money(@overview.summary.avg_check)}
          </.stat_card>
        </div>
        <p
          :if={(@compare? and @overview.comparison) && @overview.comparison.state == :ready}
          id="statistics-sales-comparison-values"
          class="text-sm text-base-content/70"
        >
          {gettext("Comparison period")}: {format_period(@overview.comparison.period)} · {gettext(
            "Sales after refunds"
          )}: {OrderHelpers.money(@overview.comparison.summary.revenue)} · {gettext("Orders")}: {@overview.comparison.summary.orders_count} · {gettext(
            "Average check"
          )}: {OrderHelpers.money(@overview.comparison.summary.avg_check)}
        </p>
        <p
          :if={(@compare? and @overview.comparison) && @overview.comparison.state == :partial}
          id="statistics-comparison-partial"
          class="text-sm text-warning"
        >
          {gettext("Some daily totals are updating. The latest published figures are shown.")}
        </p>
        <p
          :if={
            (@compare? and @overview.comparison) && @overview.comparison.state == :ready &&
              @overview.comparison.summary.orders_count == 0
          }
          class="text-sm text-base-content/60"
        >
          {gettext("The comparison period has no completed orders; percentage change is unavailable.")}
        </p>
        <div
          id="statistics-sales-charts"
          class={["grid grid-cols-1 gap-3", @granularity == "month" && "xl:grid-cols-3"]}
        >
          <.chart
            :for={metric <- [:revenue, :orders, :avg_check]}
            daily={@overview.daily}
            comparison={
              if(@compare? && @overview.comparison && @overview.comparison.state == :ready,
                do: @overview.comparison
              )
            }
            granularity={@granularity}
            metric={metric}
          />
        </div>
        <div class="grid gap-3 md:grid-cols-2">
          <section
            id="statistics-top-products"
            class="rounded-box border border-base-300 bg-base-100 p-4"
          >
            <h2 class="font-semibold">{gettext("Top 5 products")}</h2>
            <p class="text-xs text-base-content/60">
              {gettext(
                "Product amounts are before refunds; order refunds are shown separately in the sales total."
              )}
            </p>
            <div :for={row <- @top_products} class="mt-2 flex justify-between gap-3 text-sm">
              <span>{row.title}</span><span class="tabular-nums">{row.quantity} · {OrderHelpers.money(
                row.revenue
              )}</span>
            </div>
            <.link patch={tab_path(assigns, "products")} class="link link-primary text-sm">{gettext(
              "All products"
            )}</.link>
          </section>
          <section
            id="statistics-top-categories"
            class="rounded-box border border-base-300 bg-base-100 p-4"
          >
            <h2 class="font-semibold">{gettext("Top 5 categories")}</h2>
            <p class="text-xs text-base-content/60">
              {gettext(
                "Category amounts are before refunds; order refunds are shown separately in the sales total."
              )}
            </p>
            <div :for={row <- @top_categories} class="mt-2 flex justify-between gap-3 text-sm">
              <span>{row.title || gettext("Without category")}</span><span class="tabular-nums">{row.quantity} · {OrderHelpers.money(
                row.revenue
              )}</span>
            </div>
            <.link patch={tab_path(assigns, "categories")} class="link link-primary text-sm">{gettext(
              "All categories"
            )}</.link>
          </section>
        </div>
        <nav class="flex flex-wrap gap-2" aria-label={gettext("Sales details")}>
          <.link
            :if={"channels" in @overview.visibility.reports}
            navigate={report_path(assigns, "channels")}
            class="btn btn-sm btn-outline"
          >{tab_label("channels")}</.link>
          <.link
            :if={
              Identity.can?(@current_staff, "statistics.network") and
                Features.enabled?("analytics_franchise", :franchise)
            }
            navigate={report_path(assigns, "comparison")}
            class="btn btn-sm btn-outline"
          >{gettext("Compare branches")}</.link>
        </nav>
        <div class="grid gap-3 md:grid-cols-2">
          <section
            :if={@overview.visibility.fulfillment != []}
            id="statistics-fulfillment"
            class="rounded-box border border-base-300 bg-base-100 p-4"
          >
            <h2 class="font-semibold">{gettext("Fulfillment method")}</h2>
            <div
              :for={
                row <- Enum.filter(@by_fulfillment, &(&1.key in @overview.visibility.fulfillment))
              }
              class="mt-2 flex justify-between gap-3 text-sm"
            >
              <span>{fulfillment_label(row.key)}</span>
              <span class="tabular-nums">{row.orders} · {OrderHelpers.money(row.revenue)}</span>
            </div>
          </section>
          <section id="statistics-payment" class="rounded-box border border-base-300 bg-base-100 p-4">
            <h2 class="font-semibold">{gettext("Payment method")}</h2>
            <div :for={row <- @by_payment} class="mt-2 flex justify-between gap-3 text-sm">
              <span>{payment_label(row.key)}</span>
              <span class="tabular-nums">{row.orders} · {OrderHelpers.money(row.revenue)}</span>
            </div>
          </section>
        </div>
        <div class="grid gap-3 md:grid-cols-2">
          <section
            :if={@by_source != []}
            id="statistics-order-source"
            class="rounded-box border border-base-300 bg-base-100 p-4"
          >
            <h2 class="font-semibold">{gettext("Order source")}</h2>
            <div :for={row <- @by_source} class="mt-2 flex justify-between gap-3 text-sm">
              <span>{source_label(row.key)}</span>
              <span class="tabular-nums">{row.orders} · {OrderHelpers.money(row.revenue)}</span>
            </div>
          </section>
          <section
            :if={@by_destination != []}
            id="statistics-transfer-destination"
            class="rounded-box border border-base-300 bg-base-100 p-4"
          >
            <h2 class="font-semibold">{gettext("Transfer destination")}</h2>
            <div :for={row <- @by_destination} class="mt-2 flex justify-between gap-3 text-sm">
              <span>{destination_label(row.key)}</span>
              <span class="tabular-nums">{row.orders} · {OrderHelpers.money(row.revenue)}</span>
            </div>
          </section>
        </div>
        <p :if={@overview.visibility.channels != []} class="text-xs text-base-content/60">
          {gettext(
            "Order source describes where an order began; sending it to a CRM does not change that source."
          )}
        </p>
      </section>

      <section
        :if={@tab == "products" and is_nil(@period_error)}
        id="statistics-products-detail"
        class="space-y-3"
      >
        <.link patch={tab_path(assigns, "sales")} class="btn btn-sm btn-ghost">{gettext(
          "Back to sales"
        )}</.link>
        <p class="text-sm text-base-content/70">
          {gettext(
            "Product amounts are before refunds; order refunds are shown separately in the sales total."
          )}
        </p>
        <div class="flex flex-wrap gap-2">
          <.link
            patch={tab_path(assigns, "products", %{"sort" => "revenue"})}
            class={["btn btn-sm", @sort == :revenue && "btn-primary"]}
          >{gettext("By revenue")}</.link>
          <.link
            patch={tab_path(assigns, "products", %{"sort" => "quantity"})}
            class={["btn btn-sm", @sort == :quantity && "btn-primary"]}
          >{gettext("By quantity")}</.link>
        </div>
        <.table
          id="statistics-products"
          rows={@products}
          row_id={fn row -> "statistics-product-#{row.key}" end}
          empty_title={gettext("No completed orders in this period")}
        >
          <:col :let={row} key="product" label={gettext("Product")}>{row.title}</:col>
          <:col :let={row} key="quantity" label={gettext("Qty")} numeric>{row.quantity}</:col>
          <:col :let={row} key="orders" label={gettext("Orders")} numeric>{row.orders}</:col>
          <:col :let={row} key="revenue" label={gettext("Before refunds")} numeric>
            {OrderHelpers.money(row.revenue)}
          </:col>
        </.table>
      </section>

      <section
        :if={@tab == "categories" and is_nil(@period_error)}
        id="statistics-categories-detail"
        class="space-y-3"
      >
        <.link patch={tab_path(assigns, "sales")} class="btn btn-sm btn-ghost">{gettext(
          "Back to sales"
        )}</.link>
        <p class="text-sm text-base-content/70">
          {gettext(
            "Category amounts are before refunds; order refunds are shown separately in the sales total."
          )}
        </p>
        <.table
          id="statistics-categories"
          rows={@categories}
          row_id={fn row -> "statistics-category-#{row.key || "none"}" end}
          empty_title={gettext("No completed orders in this period")}
        >
          <:col :let={row} key="category" label={gettext("Category")}>
            {row.title || gettext("Without category")}
          </:col>
          <:col :let={row} key="quantity" label={gettext("Qty")} numeric>{row.quantity}</:col>
          <:col :let={row} key="orders" label={gettext("Orders")} numeric>{row.orders}</:col>
          <:col :let={row} key="revenue" label={gettext("Before refunds")} numeric>
            {OrderHelpers.money(row.revenue)}
          </:col>
        </.table>
      </section>
    </div>
    """
  end

  defp tab_label("sales"), do: pgettext("sales statistics", "Summary")
  defp tab_label("products"), do: gettext("Products")
  defp tab_label("categories"), do: gettext("Categories")
  defp tab_label("funnel"), do: gettext("Order funnel")
  defp tab_label("sources"), do: gettext("Sources")
  defp tab_label("customers"), do: gettext("Buyers")
  defp tab_label("channels"), do: gettext("Sales channels")
  defp tab_label("comparison"), do: gettext("Comparison")
  defp tab_label("franchise"), do: gettext("Branch comparison")
  defp tab_label("overview"), do: gettext("Overview")
  defp tab_label("orders"), do: gettext("Completed orders")
  defp tab_label("cancelled"), do: gettext("Cancellations")
  defp tab_label("refunds"), do: gettext("Refunds")
end
