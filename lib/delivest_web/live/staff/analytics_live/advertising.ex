defmodule DelivestWeb.Staff.AnalyticsLive.Advertising do
  use DelivestWeb, :live_view

  alias Delivest.Identity
  alias Delivest.Integrations.YandexAds
  alias Delivest.Integrations.YandexAds.Campaigns

  on_mount {DelivestWeb.Hooks.Permission, "statistics.read"}
  on_mount {DelivestWeb.Hooks.Permission, "statistics.network"}

  @impl true
  def mount(_params, _session, socket) do
    today = Delivest.LocalTime.today(Delivest.LocalTime.timezone())

    {:ok,
     socket
     |> assign(
       page_title: gettext("Advertising analytics"),
       from: Date.add(today, -6),
       to: today,
       error: nil,
       importing: false,
       refresh_timer: nil,
       refresh_epoch: 0,
       refresh_attempts: 0,
       refresh_retry?: false,
       can_import: Identity.can?(socket.assigns.current_staff, "admin")
     )
     |> attach_hook(:advertising_permissions, :handle_info, &recheck_permissions/2)
     |> load_report()}
  end

  defp recheck_permissions(event, socket) when event in [:role_updated, :staff_updated] do
    if permitted?(socket.assigns.current_staff) do
      period_form = socket.assigns.period

      {:cont,
       socket
       |> cancel_refresh()
       |> assign(refresh_epoch: socket.assigns.refresh_epoch + 1, refresh_attempts: 0)
       |> load_report()
       |> assign(period: period_form)}
    else
      {:halt, redirect(cancel_refresh(socket), to: ~p"/staff")}
    end
  end

  defp recheck_permissions(_event, socket), do: {:cont, socket}

  defp permitted?(staff),
    do: Identity.can?(staff, "statistics.read") and Identity.can?(staff, "statistics.network")

  @impl true
  def handle_params(params, _uri, socket) do
    {from, to} = Delivest.Analytics.resolve_period(params["period"], params["from"], params["to"])

    {:noreply,
     socket
     |> cancel_refresh()
     |> assign(
       from: from,
       to: to,
       refresh_epoch: socket.assigns.refresh_epoch + 1,
       refresh_attempts: 0,
       refresh_retry?: false
     )
     |> load_report()}
  end

  @impl true
  def handle_event("filter", %{"period" => attrs}, socket) do
    with {:ok, from} <- Date.from_iso8601(attrs["from"] || ""),
         {:ok, to} <- Date.from_iso8601(attrs["to"] || ""),
         true <- Date.diff(to, from) in 0..365 do
      {:noreply,
       socket
       |> assign(error: nil)
       |> push_patch(
         to:
           ~p"/staff/analytics/advertising?#{%{period: "custom", from: Date.to_iso8601(from), to: Date.to_iso8601(to)}}"
       )}
    else
      _ -> {:noreply, assign(socket, error: gettext("Choose a period of up to 366 days."))}
    end
  end

  def handle_event("refresh", _params, socket),
    do: {:noreply, socket |> assign(refresh_attempts: 0, refresh_retry?: false) |> load_report()}

  def handle_event("import", _params, socket) do
    case YandexAds.request_costs(
           socket.assigns.current_staff,
           socket.assigns.from,
           socket.assigns.to
         ) do
      {:ok, _job} ->
        {:noreply,
         put_flash(
           socket,
           :info,
           gettext("Cost import queued. Refresh the report after processing.")
         )}

      {:error, _reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Import unavailable. Check integration settings and access.")
         )}
    end
  end

  defp load_campaigns(socket) do
    report =
      case Campaigns.report(socket.assigns.current_staff, socket.assigns.from, socket.assigns.to) do
        {:ok, report} -> report
        _ -> %{campaigns: [], truncated: false, f04_state: :not_collected}
      end

    bindings =
      case Campaigns.list(socket.assigns.current_staff) do
        {:ok, result} -> result.bindings
        _ -> []
      end

    socket
    |> assign(campaign_report: report)
    |> stream(:campaigns, report.campaigns, reset: true, dom_id: &"campaign-#{&1.campaign_id}")
    |> stream(:bindings, bindings, reset: true, dom_id: &"binding-#{&1.advertising_link_id}")
  end

  @impl true
  def handle_info({:refresh_advertising, epoch}, socket) do
    if epoch == socket.assigns.refresh_epoch do
      period_form = socket.assigns.period

      {:noreply,
       socket
       |> assign(refresh_attempts: socket.assigns.refresh_attempts + 1)
       |> load_report()
       |> assign(period: period_form)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_, socket), do: {:noreply, socket}

  defp cancel_refresh(socket) do
    if socket.assigns[:refresh_timer], do: Process.cancel_timer(socket.assigns.refresh_timer)
    assign(socket, refresh_timer: nil)
  end

  defp schedule_refresh(socket) do
    socket = cancel_refresh(socket)

    pending? =
      Map.get(socket.assigns.campaign_report, :refresh_pending, false) or
        Map.get(socket.assigns.report, :refresh_pending, false)

    socket = if pending?, do: socket, else: assign(socket, refresh_attempts: 0)
    exhausted? = pending? and socket.assigns.refresh_attempts >= 5
    today = Delivest.LocalTime.today(Delivest.LocalTime.timezone())

    current? =
      Date.compare(socket.assigns.from, today) != :gt and
        Date.compare(socket.assigns.to, today) != :lt

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
        do:
          Process.send_after(self(), {:refresh_advertising, socket.assigns.refresh_epoch}, delay)

    assign(socket, refresh_timer: timer, refresh_retry?: exhausted?)
  end

  @impl true
  def terminate(_, socket) do
    if socket.assigns[:refresh_timer], do: Process.cancel_timer(socket.assigns.refresh_timer)
    :ok
  end

  defp load_report(socket) do
    case YandexAds.report(socket.assigns.current_staff, socket.assigns.from, socket.assigns.to) do
      {:ok, report} ->
        socket
        |> assign(
          report: report,
          report_available: true,
          period:
            to_form(
              %{
                "from" => Date.to_iso8601(socket.assigns.from),
                "to" => Date.to_iso8601(socket.assigns.to)
              },
              as: :period
            ),
          costs_empty: report.costs == [],
          cost_total:
            Map.get(
              report,
              :cost_total_micros,
              Enum.reduce(report.costs, 0, &(&1.cost_micros + &2))
            ),
          costs_truncated: Map.get(report, :costs_truncated, false)
        )
        |> stream(:costs, report.costs, reset: true, dom_id: &"cost-#{&1.day}-#{&1.campaign_id}")
        |> assign(delivery_issue_count: length(Map.get(report, :delivery_issues, [])))
        |> load_campaigns()
        |> schedule_refresh()

      {:error, _reason} ->
        socket
        |> assign(
          report_available: false,
          period:
            to_form(
              %{
                "from" => Date.to_iso8601(socket.assigns.from),
                "to" => Date.to_iso8601(socket.assigns.to)
              },
              as: :period
            ),
          error: gettext("Advertising data is unavailable for this account.")
        )
        |> stream(:costs, [], reset: true)
    end
  end

  def staff_page_header(assigns) do
    ~H"""
    <.page_header title={gettext("Advertising analytics")}>
      <:actions>
        <button type="button" phx-click="refresh" id="advertising-refresh" class="btn btn-outline">{gettext(
          "Refresh"
        )}</button>
      </:actions>
    </.page_header>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <nav id="sources-advertising-tabs" class="tabs">
      <.link
        navigate={"/staff/analytics/sources?" <> URI.encode_query(%{"period" => "custom", "from" => @from, "to" => @to})}
        class="tab"
      >{gettext("Sources")}</.link>
      <span class="tab tab-active">{gettext("Campaigns")}</span>
    </nav>

    <div class="space-y-6">
      <.form
        for={@period}
        id="advertising-period"
        phx-submit="filter"
        class="flex flex-wrap items-end gap-3 rounded-box border border-base-300 bg-base-100 p-5"
      >
        <.input field={@period[:from]} type="date" label={gettext("From")} />
        <.input field={@period[:to]} type="date" label={gettext("To")} />
        <button type="submit" class="btn btn-primary">{gettext("Apply")}</button>
        <button
          :if={@can_import}
          type="button"
          phx-click="import"
          id="advertising-import"
          class="btn btn-outline"
        >{gettext("Import costs")}</button>
      </.form>
      <p :if={@error} id="advertising-error" role="alert" class="text-error">{@error}</p>

      <%= if @report_available do %>
        <section id="advertising-summary" class="grid gap-3 sm:grid-cols-3">
          <div class="rounded-box border border-base-300 bg-base-100 p-5">
            <p class="text-sm text-base-content/60">{gettext("Advertising costs")}</p>
            <p class="text-2xl font-bold">{money(@cost_total, 1_000_000)} ₽</p>
          </div>
          <div class="rounded-box border border-base-300 bg-base-100 p-5">
            <p class="text-sm text-base-content/60">{gettext("Completed orders")}</p>
            <p class="text-2xl font-bold">{@report.completed_orders || "—"}</p>
          </div>
          <div class="rounded-box border border-base-300 bg-base-100 p-5">
            <p class="text-sm text-base-content/60">{gettext("Net completed revenue")}</p>
            <p class="text-2xl font-bold">{money(@report.net_revenue, 100)} ₽</p>
          </div>
        </section>

        <section
          id="advertising-campaign-report"
          class="overflow-x-auto rounded-box border border-base-300 bg-base-100 p-5 space-y-3"
        >
          <h2 class="text-lg font-bold">{gettext("Campaign results from trusted links")}</h2>
          <p class="text-sm text-base-content/60">
            {gettext(
              "Only existing trusted Delivest links bound to a campaign are counted. URL labels alone do not establish a campaign match. Results use F04 reports and their collection coverage."
            )}
          </p>
          <p class="text-sm text-base-content/60">
            {gettext(
              "ROAS is attributed net revenue divided by advertising cost. CPA is cost per completed order. Neither metric proves incremental sales."
            )}
          </p>
          <p id="advertising-campaign-coverage" class="text-sm text-base-content/60">
            {gettext("F04 report state")}: {report_state(@campaign_report.f04_state)}
          </p>
          <p
            :if={
              (Map.get(@campaign_report, :refresh_pending, false) or
                 Map.get(@report, :refresh_pending, false)) and not @refresh_retry?
            }
            id="advertising-report-refreshing"
            role="status"
            class="text-sm text-base-content/60"
          >
            {gettext("Updating report…")}
          </p>
          <p
            :if={@refresh_retry?}
            id="advertising-report-refresh-delayed"
            class="text-sm text-warning"
          >
            {gettext("The report is taking longer to update. Try again shortly.")}
          </p>
          <p :if={@campaign_report.truncated} class="text-sm text-warning">
            {gettext("The campaign table is limited. Shorten the period for more detail.")}
          </p>
          <table class="table">
            <thead>
              <tr>
                <th>{gettext("Campaign")}</th><th>{gettext("Cost")}</th><th>
                  {gettext("Completed orders")}
                </th><th>{gettext("Net completed revenue")}</th><th>ROAS</th><th>CPA</th>
              </tr>
            </thead>
            <tbody id="advertising-campaigns" phx-update="stream">
              <tr :for={{id, row} <- @streams.campaigns} id={id}>
                <td>
                  {row.campaign_name}
                  <span class="text-xs text-base-content/50">{row.campaign_id}</span>
                </td>
                <td>{money(row.cost_micros, 1_000_000)} ₽</td>
                <td>{row.completed_orders || "—"}</td><td>{money(row.net_revenue, 100)} ₽</td>
                <td>{ratio(row.roas)}</td><td>{money(row.cpa_micros, 1_000_000)} ₽</td>
              </tr>
            </tbody>
          </table>
          <h3 class="font-bold">{gettext("Current campaign mappings")}</h3>
          <div id="advertising-bindings" phx-update="stream" class="space-y-2">
            <div :for={{id, binding} <- @streams.bindings} id={id} class="text-sm">
              {binding.link_name} → {binding.campaign_id}
            </div>
          </div>
          <.link
            :if={@can_import}
            id="advertising-mapping-settings"
            navigate={~p"/staff/integrations/yandex-ads#yandex-campaign-mappings"}
            class="link"
          >
            {gettext("Manage campaign mappings in integration settings")}
          </.link>
        </section>

        <section
          id="advertising-coverage"
          class="rounded-box border border-base-300 bg-base-100 p-5 space-y-2 text-sm"
        >
          <p>
            {gettext(
              "These are account costs and completed orders, not proof that advertising caused those sales."
            )}
          </p>
          <p>
            {gettext(
              "ROAS and CPA are unavailable until campaign attribution is verified. Shared campaign costs are counted once, without an invented branch allocation."
            )}
          </p>
          <p>
            {gettext(
              "Orders with captured advertising identifiers: %{count}. Captured identifiers do not confirm a match in Yandex.",
              count: @report.identified_orders
            )}
          </p>
          <p
            :if={Map.get(@report, :f04_state) not in [nil, :ready, :empty]}
            id="advertising-f04-state"
          >
            {gettext(
              "Order totals depend on the existing F04 report. Its data may be disabled, incomplete or stale."
            )}
            <.link
              id="advertising-order-report"
              navigate={
                ~p"/staff/analytics/comparison?#{%{period: "custom", from: Date.to_iso8601(@from), to: Date.to_iso8601(@to)}}"
              }
              class="link"
            >{gettext("Branch comparison")}</.link>
          </p>
          <p>
            {gettext(
              "Costs use the configured advertising account time zone and VAT setting. Order periods use the existing Delivest reporting rules."
            )}
          </p>
        </section>

        <section class="overflow-x-auto rounded-box border border-base-300 bg-base-100 p-5">
          <h2 class="mb-3 text-lg font-bold">{gettext("Costs by campaign and day")}</h2>
          <p :if={@costs_truncated} id="advertising-truncated" class="text-sm text-base-content/60">
            {gettext(
              "The table shows the first 250 rows. Totals include the full period; choose a shorter period for details."
            )}
          </p>
          <p :if={@costs_empty} id="advertising-no-costs" class="text-base-content/60">
            {gettext(
              "No imported costs for this period. This does not mean the advertising spend was zero."
            )}
          </p>
          <table :if={!@costs_empty} class="table">
            <thead>
              <tr>
                <th>{gettext("Date")}</th><th>{gettext("Campaign")}</th><th>
                  {gettext("Impressions")}
                </th><th>{gettext("Clicks")}</th><th>{gettext("Cost")}</th>
              </tr>
            </thead>
            <tbody id="advertising-costs" phx-update="stream">
              <tr :for={{id, row} <- @streams.costs} id={id}>
                <td>{row.day}</td><td>
                  {row.campaign_name}
                  <span class="text-xs text-base-content/50">{row.campaign_id}</span>
                </td>
                <td>{row.impressions}</td><td>{row.clicks}</td><td>
                  {money(row.cost_micros, 1_000_000)} {row.currency}
                </td>
              </tr>
            </tbody>
          </table>
        </section>

        <section
          id="advertising-delivery-health"
          class="rounded-box border border-base-300 bg-base-100 p-5 space-y-2"
        >
          <h2 class="font-bold">{gettext("Conversion delivery")}</h2>
          <p>{gettext("Recent delivery issues requiring review")}: {@delivery_issue_count}</p>
          <.link
            :if={@can_import}
            id="advertising-diagnostics-settings"
            navigate={~p"/staff/integrations/yandex-ads#yandex-delivery-diagnostics"}
            class="link"
          >
            {gettext("Review delivery diagnostics in integration settings")}
          </.link>
        </section>
      <% end %>
    </div>
    """
  end

  defp money(value, divisor) when is_integer(value) do
    value
    |> Decimal.new()
    |> Decimal.div(divisor)
    |> Decimal.round(2)
    |> Decimal.to_string(:normal)
  end

  defp money(%Decimal{} = value, divisor),
    do: value |> Decimal.div(divisor) |> Decimal.round(2) |> Decimal.to_string(:normal)

  defp money(nil, _divisor), do: "—"

  defp ratio(nil), do: "—"
  defp ratio(value), do: value |> Decimal.round(2) |> Decimal.to_string(:normal)

  defp report_state(:ready), do: gettext("Ready")
  defp report_state(:empty), do: gettext("No matching data")
  defp report_state(:partial), do: gettext("Incomplete collection")
  defp report_state(:stale), do: gettext("Data is stale")
  defp report_state(_), do: gettext("Not collected or disabled")
end
