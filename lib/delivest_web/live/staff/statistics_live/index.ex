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
    {:ok,
     socket
     |> assign(
       page_title: gettext("Sales statistics"),
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
        refresh_retry?: false
      )

    global? = not String.starts_with?(URI.parse(url).path, "/staff/b/")
    section = params["section"]
    legacy_tab = params["tab"]
    branch = if global?, do: nil, else: socket.assigns.current_branch
    socket = assign(socket, current_branch: branch, global_statistics?: global?, section: section)

    cond do
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

      true ->
        visible_tabs = visible_tabs(socket)
        tab = if params["tab"] in visible_tabs, do: params["tab"], else: List.first(visible_tabs)

        preset =
          if params["period"] in Analytics.presets(), do: params["period"], else: "week"

        {period, period_error} =
          if preset == "custom" do
            case Analytics.validate_custom_period(params["from"], params["to"]) do
              {:ok, period} ->
                {period, nil}

              {:error, :invalid_period} ->
                {Analytics.resolve_period("week", nil, nil, branch && branch.id),
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
             if(section,
               do: tab_label(if(section == "comparison", do: "franchise", else: section)),
               else:
                 if(global?,
                   do: gettext("Sales across the network"),
                   else: gettext("Sales statistics")
                 )
             ),
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
           report_filters: report_filters(params)
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
        "period" => params["period"],
        "sort" => to_string(socket.assigns.sort),
        "compare" => socket.assigns.comparison_mode,
        "compare_from" => socket.assigns.comparison_from,
        "compare_to" => socket.assigns.comparison_to,
        "channel" => params["channel"] || socket.assigns.report_filters["channel"],
        "branch_id" => params["branch_id"] || socket.assigns.report_filters["branch_id"],
        "link_id" => params["link_id"] || socket.assigns.report_filters["link_id"],
        "link_search" => params["link_search"] || socket.assigns.report_filters["link_search"]
      }
      |> compact_query()
      |> maybe_put_custom(params, socket.assigns.period)

    {:noreply, push_patch(socket, to: statistics_path(socket.assigns, query))}
  end

  def handle_event("open_comparison", _, socket),
    do: {:noreply, assign(socket, comparison_open?: true)}

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
    if socket.assigns.tab in @report_tabs and is_nil(socket.assigns.period_error) do
      {:noreply, socket |> assign(refresh_attempts: 0, refresh_retry?: false) |> load_tab()}
    else
      {:noreply, socket}
    end
  end

  @impl true
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
      socket.assigns.tab in @report_tabs and
        Map.get(socket.assigns.report, :refresh_pending, false)

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

  defp load_tab(%{assigns: %{tab: "sales"}} = socket) do
    %{period: period, current_branch: branch} = socket.assigns
    summary = Analytics.summary(branch_scope(socket.assigns), period)

    previous =
      if socket.assigns.compare?,
        do: Analytics.summary(branch_scope(socket.assigns), socket.assigns.comparison_period),
        else: nil

    assign(socket,
      summary: summary,
      previous: previous,
      crm_split:
        branch && Gateway.active?(branch) &&
          Analytics.crm_split(branch_scope(socket.assigns), period),
      daily: Analytics.daily(branch_scope(socket.assigns), period),
      hourly: Analytics.hourly(branch_scope(socket.assigns), period),
      by_fulfillment:
        Analytics.breakdown(branch_scope(socket.assigns), period, :fulfillment_type),
      by_payment: Analytics.breakdown(branch_scope(socket.assigns), period, :payment_method)
    )
    |> schedule_report_refresh()
  end

  defp load_tab(%{assigns: %{tab: "products"}} = socket) do
    %{period: period, sort: sort} = socket.assigns

    assign(socket,
      products:
        Analytics.top_products(branch_scope(socket.assigns), period, limit: 100, sort_by: sort)
    )
    |> schedule_report_refresh()
  end

  defp load_tab(%{assigns: %{tab: "categories"}} = socket) do
    %{period: period} = socket.assigns

    assign(socket, categories: Analytics.categories(branch_scope(socket.assigns), period))
    |> schedule_report_refresh()
  end

  defp load_tab(%{assigns: %{tab: tab}} = socket) when tab in @report_tabs do
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

  defp branch_scope(%{current_branch: %{id: id}}), do: id

  defp branch_scope(assigns) do
    ids = Enum.map(assigns.staff_branches, & &1.id)

    case {assigns.report_filters["branch_id"], assigns.report_filters["branch_ids"]} do
      {id, _} when is_binary(id) and id != "" ->
        Enum.filter(ids, &(&1 == id))

      {id, nil} when id in [nil, ""] ->
        ids

      {id, selected} when id in [nil, ""] and is_list(selected) ->
        Enum.filter(ids, &(&1 in selected))

      _ ->
        []
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
        "compare" => assigns.comparison_mode,
        "compare_from" => assigns.comparison_from,
        "compare_to" => assigns.comparison_to,
        "channel" => assigns.report_filters["channel"],
        "branch_id" => assigns.report_filters["branch_id"],
        "branch_ids" => assigns.report_filters["branch_ids"],
        "link_id" => assigns.report_filters["link_id"],
        "link_search" => assigns.report_filters["link_search"]
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

  defp confirm_time(nil), do: "—"
  defp confirm_time(seconds) when seconds < 60, do: gettext("%{n} s", n: seconds)
  defp confirm_time(seconds), do: gettext("%{n} min", n: Float.round(seconds / 60, 1))

  defp short_date(date), do: Calendar.strftime(date, "%d.%m")

  defp label_every(rows), do: max(div(length(rows) + 11, 12), 1)

  defp breakdown_label(:fulfillment_type, key), do: OrderHelpers.fulfillment_label(key)
  defp breakdown_label(:payment_method, key), do: OrderHelpers.payment_label(key)

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
          {format_period(@period)}
        </p>
      </div>
      <div class="flex min-w-0 flex-wrap items-center gap-2 lg:ml-auto lg:justify-end">
        <.form
          for={@form}
          id="statistics-filter"
          phx-change="filter"
          class="flex min-w-0 flex-wrap items-center gap-2 [&>fieldset]:mb-0 [&>fieldset]:w-auto"
        >
          <select
            name="period"
            aria-label={gettext("Period")}
            class="select select-bordered select-sm w-40"
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
              class="input input-bordered input-sm w-36"
            />
            <input
              type="date"
              name="to"
              value={@custom_to}
              class="input input-bordered input-sm w-36"
            />
          <% end %>
          <.input
            :if={@global_statistics? and @tab in ~w(sales products categories)}
            field={@form[:branch_id]}
            id="statistics-network-branch"
            type="select"
            prompt={gettext("All branches")}
            options={Enum.map(@staff_branches, &{&1.name, &1.id})}
            class="select select-bordered select-sm w-44"
          />
          <.input
            :if={@tab in ~w(channels comparison franchise)}
            field={@form[:channel]}
            type="select"
            prompt={gettext("All channels")}
            options={channel_options()}
            class="select select-bordered select-sm w-36"
          />
          <.input
            :if={@tab == "sources"}
            field={@form[:link_search]}
            type="text"
            placeholder={gettext("Find advertising link")}
            class="input input-bordered input-sm w-40"
          />
          <.input
            :if={@tab == "sources"}
            field={@form[:link_id]}
            type="select"
            prompt={gettext("All advertising links")}
            options={@link_options}
            class="input input-bordered input-sm w-48"
          />
        </.form>
        <button
          :if={@tab == "sales"}
          id="statistics-compare"
          type="button"
          phx-click="open_comparison"
          class="btn btn-sm btn-outline"
        >{gettext("Compare")}</button>
      </div>
    </div>
    """
  end

  def staff_page_navigation(_assigns), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-3">
      <nav
        :if={is_nil(@section) and @visible_tabs != []}
        id="statistics-sales-tabs"
        aria-label={gettext("Statistics reports")}
        class="overflow-x-auto whitespace-nowrap"
      >
        <div role="tablist" class="tabs tabs-sm">
          <.link
            :for={tab <- @visible_tabs}
            id={"statistics-tab-#{tab}"}
            patch={tab_path(assigns, tab)}
            role="tab"
            class={["tab", @tab == tab && "tab-active"]}
            aria-current={@tab == tab && "page"}
          >{tab_label(tab)}</.link>
        </div>
      </nav>
      <nav
        :if={@section == "sources" and Identity.can?(@current_staff, "statistics.network")}
        id="sources-advertising-tabs"
        class="tabs tabs-sm"
      >
        <span class="tab tab-active">{gettext("Sources")}</span>
        <.link
          navigate={"/staff/analytics/advertising?" <> URI.encode_query(%{"period" => @preset, "from" => elem(@period, 0), "to" => elem(@period, 1)})}
          class="tab"
        >{gettext("Campaigns")}</.link>
      </nav>
      <section
        :if={@tab == "sales" and @comparison_open?}
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
        page_path={fn page -> tab_path(assigns, @tab, %{"page" => Integer.to_string(page)}) end}
      />

      <%= if @tab == "sales" and is_nil(@period_error) do %>
        <.empty_state :if={@summary.orders_count == 0} title={gettext("No sales in this period")} />
        <div class="grid grid-cols-2 xl:grid-cols-4 gap-3">
          <.stat_card
            icon="hero-banknotes"
            label={gettext("Revenue")}
            delta={@compare? && delta(@summary.revenue, @previous.revenue)}
            hint={
              @compare? &&
                gettext("Comparison: %{value}", value: OrderHelpers.money(@previous.revenue))
            }
          >
            {OrderHelpers.money(@summary.revenue)}
          </.stat_card>
          <.stat_card
            icon="hero-shopping-bag"
            label={gettext("Orders")}
            delta={@compare? && delta(@summary.orders_count, @previous.orders_count)}
            hint={
              if @compare?,
                do: gettext("Comparison: %{value}", value: @previous.orders_count),
                else: excluded_hint(@summary)
            }
          >
            {@summary.orders_count}
          </.stat_card>
          <.stat_card
            icon="hero-receipt-percent"
            label={gettext("Average check")}
            delta={@compare? && delta(@summary.avg_check, @previous.avg_check)}
            hint={
              @compare? &&
                gettext("Comparison: %{value}", value: OrderHelpers.money(@previous.avg_check))
            }
          >
            {OrderHelpers.money(@summary.avg_check)}
          </.stat_card>
          <.stat_card
            icon="hero-cube"
            label={gettext("Items sold")}
            delta={@compare? && delta(@summary.items_sold, @previous.items_sold)}
            hint={@compare? && gettext("Comparison: %{value}", value: @previous.items_sold)}
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

          <.table
            id="statistics-products"
            rows={Enum.with_index(@products, 1)}
            row_id={fn {_row, index} -> "statistics-product-#{index}" end}
            empty_title={gettext("No sales in this period")}
          >
            <:col :let={{_row, index}} key="position" label="#">{index}</:col>
            <:col :let={{row, _index}} key="product" label={gettext("Product")}>{row.title}</:col>
            <:col :let={{row, _index}} key="category" label={gettext("Category")} secondary>
              {row.category_name || "—"}
            </:col>
            <:col :let={{row, _index}} key="quantity" label={gettext("Qty")} numeric>
              {row.quantity}
            </:col>
            <:col :let={{row, _index}} key="orders" label={gettext("Orders")} numeric secondary>
              {row.orders}
            </:col>
            <:col :let={{row, _index}} key="revenue" label={gettext("Revenue")} numeric>
              {OrderHelpers.money(row.revenue)}
            </:col>
            <:col :let={{row, _index}} key="share" label={gettext("Share of revenue")} secondary>
              <.share_bar value={row.share} />
            </:col>
          </.table>
        </.card>
      <% end %>

      <%= if @tab == "categories" and is_nil(@period_error) do %>
        <.card class="overflow-x-auto">
          <.table
            id="statistics-categories"
            rows={Enum.with_index(@categories, 1)}
            row_id={fn {_row, index} -> "statistics-category-#{index}" end}
            empty_title={gettext("No sales in this period")}
          >
            <:col :let={{row, _index}} key="category" label={gettext("Category")}>
              {row.category_name || gettext("Without category")}
            </:col>
            <:col :let={{row, _index}} key="products" label={gettext("Products")} numeric secondary>
              {row.products}
            </:col>
            <:col :let={{row, _index}} key="quantity" label={gettext("Qty")} numeric>
              {row.quantity}
            </:col>
            <:col :let={{row, _index}} key="orders" label={gettext("Orders")} numeric secondary>
              {row.orders}
            </:col>
            <:col :let={{row, _index}} key="revenue" label={gettext("Revenue")} numeric>
              {OrderHelpers.money(row.revenue)}
            </:col>
            <:col :let={{row, _index}} key="share" label={gettext("Share of revenue")} secondary>
              <.share_bar value={row.share} />
            </:col>
          </.table>
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

  defp tab_label("sales"), do: pgettext("sales statistics", "Summary")
  defp tab_label("products"), do: gettext("Products")
  defp tab_label("categories"), do: gettext("Categories")
  defp tab_label("funnel"), do: gettext("Order funnel")
  defp tab_label("sources"), do: gettext("Sources")
  defp tab_label("customers"), do: gettext("Buyers")
  defp tab_label("channels"), do: gettext("Sales channels")
  defp tab_label("comparison"), do: gettext("Comparison")
  defp tab_label("franchise"), do: gettext("Branch comparison")
end
