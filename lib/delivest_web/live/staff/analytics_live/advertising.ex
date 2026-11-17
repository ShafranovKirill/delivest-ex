defmodule DelivestWeb.Staff.AnalyticsLive.Advertising do
  use DelivestWeb, :live_view

  alias Delivest.Identity
  alias Delivest.Integrations.YandexAds
  alias Delivest.Integrations.YandexAds.Campaigns

  on_mount {DelivestWeb.Hooks.Permission, "statistics.read"}
  on_mount {DelivestWeb.Hooks.Permission, "statistics.network"}

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()

    {:ok,
     socket
     |> assign(
       page_title: gettext("Advertising analytics"),
       from: Date.add(today, -6),
       to: today,
       error: nil,
       importing: false,
       can_import: Identity.can?(socket.assigns.current_staff, "admin")
     )
     |> attach_hook(:advertising_permissions, :handle_info, &recheck_permissions/2)
     |> load_report()}
  end

  defp recheck_permissions(event, socket) when event in [:role_updated, :staff_updated] do
    if permitted?(socket.assigns.current_staff) do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: ~p"/staff")}
    end
  end

  defp recheck_permissions(_event, socket), do: {:cont, socket}

  defp permitted?(staff),
    do: Identity.can?(staff, "statistics.read") and Identity.can?(staff, "statistics.network")

  @impl true
  def handle_event("filter", %{"period" => attrs}, socket) do
    with {:ok, from} <- Date.from_iso8601(attrs["from"] || ""),
         {:ok, to} <- Date.from_iso8601(attrs["to"] || ""),
         true <- Date.diff(to, from) in 0..365 do
      {:noreply, socket |> assign(from: from, to: to, error: nil) |> load_report()}
    else
      _ -> {:noreply, assign(socket, error: gettext("Choose a period of up to 366 days."))}
    end
  end

  def handle_event("refresh", _params, socket), do: {:noreply, load_report(socket)}

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

  def handle_event("reconcile", %{"reconcile" => attrs}, socket) do
    case YandexAds.reconcile_delivery(
           socket.assigns.current_staff,
           attrs["conversion_id"],
           attrs["upload_id"]
         ) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_report()
         |> put_flash(:info, gettext("Upload reconciliation queued. No new conversion was sent."))}

      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Reconciliation unavailable. Check the upload ID and current connection.")
         )}
    end
  end

  def handle_event("binding_search", %{"search" => %{"q" => query}}, socket),
    do: {:noreply, load_binding_options(socket, query)}

  def handle_event("bind_campaign", %{"binding" => attrs}, socket) do
    case Campaigns.bind(socket.assigns.current_staff, attrs["link_id"], attrs["campaign_id"]) do
      {:ok, _} ->
        {:noreply, socket |> load_report() |> put_flash(:info, gettext("Campaign link saved"))}

      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Choose an existing advertising link and an imported campaign.")
         )}
    end
  end

  def handle_event("unbind_campaign", %{"link" => link_id}, socket) do
    case Campaigns.unbind(socket.assigns.current_staff, link_id) do
      {:ok, _} ->
        {:noreply, socket |> load_report() |> put_flash(:info, gettext("Campaign link removed"))}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
    end
  end

  defp load_binding_options(socket, search) do
    options =
      case Campaigns.options(socket.assigns.current_staff, search) do
        {:ok, options} -> options
        _ -> %{links: [], campaigns: []}
      end

    assign(socket,
      binding_search: to_form(%{"q" => search}, as: :search),
      binding_form: to_form(%{"link_id" => "", "campaign_id" => ""}, as: :binding),
      link_options: Enum.map(options.links, &{"#{&1.name} · #{&1.campaign}", &1.id}),
      campaign_options:
        Enum.map(options.campaigns, &{"#{&1.campaign_name} · #{&1.campaign_id}", &1.campaign_id})
    )
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
    |> load_binding_options("")
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
        |> stream(:conversions, report.conversions,
          reset: true,
          dom_id: &"conversion-#{&1.channel}-#{&1.status}"
        )
        |> stream(:delivery_issues, Map.get(report, :delivery_issues, []), reset: true)
        |> load_campaigns()

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
        |> stream(:conversions, [], reset: true)
        |> stream(:delivery_issues, [], reset: true)
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
            {gettext("F04 report state")}: {report_state(@campaign_report.f04_state)} · {gettext(
              "Last update"
            )}: {timestamp(Map.get(@campaign_report, :last_success_at))}
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
          <%= if @can_import do %>
            <h3 class="font-bold">{gettext("Bind a trusted link to a Direct campaign")}</h3>
            <p class="text-sm text-base-content/60">
              {gettext(
                "Mappings apply to the selected account and existing link history. Import costs first; use search if the desired option is outside the first 50 results."
              )}
            </p>
            <.form
              for={@binding_search}
              id="advertising-binding-search"
              phx-submit="binding_search"
              class="flex flex-wrap items-end gap-2"
            >
              <.input field={@binding_search[:q]} label={gettext("Find a link or campaign")} />
              <button type="submit" class="btn btn-outline btn-sm">{gettext("Search")}</button>
            </.form>
            <.form
              for={@binding_form}
              id="advertising-binding-form"
              phx-submit="bind_campaign"
              class="flex flex-wrap items-end gap-2"
            >
              <.input
                field={@binding_form[:link_id]}
                type="select"
                options={@link_options}
                prompt={gettext("Choose a link")}
                label={gettext("Trusted Delivest link")}
              />
              <.input
                field={@binding_form[:campaign_id]}
                type="select"
                options={@campaign_options}
                prompt={gettext("Choose a campaign")}
                label={gettext("Direct campaign")}
              />
              <button type="submit" class="btn btn-primary btn-sm">{gettext("Save")}</button>
            </.form>
            <div id="advertising-bindings" phx-update="stream" class="space-y-2">
              <div
                :for={{id, binding} <- @streams.bindings}
                id={id}
                class="flex flex-wrap items-center gap-3 text-sm"
              >
                <span>{binding.link_name} → {binding.campaign_id}</span>
                <button
                  type="button"
                  phx-click="unbind_campaign"
                  phx-value-link={binding.advertising_link_id}
                  class="btn btn-ghost btn-sm"
                >{gettext("Remove mapping")}</button>
              </div>
            </div>
          <% end %>
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
          <p>{gettext("Last successful cost update")}: {timestamp(@report.last_cost_update)}</p>
          <p
            :if={Map.get(@report, :f04_state) not in [nil, :ready, :empty]}
            id="advertising-f04-state"
          >
            {gettext(
              "Order totals depend on the existing F04 report. Its data may be disabled, incomplete or stale."
            )}
            <.link navigate={~p"/staff/statistics?tab=franchise"} class="link">{gettext("Statistics")}</.link>
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

        <section class="rounded-box border border-base-300 bg-base-100 p-5">
          <h2 class="mb-3 text-lg font-bold">{gettext("Conversion delivery")}</h2>
          <p class="mb-3 text-sm text-base-content/60">
            {gettext(
              "Accepted, processed and matched are different outcomes. An unknown delivery is not retried as a new sale."
            )}
          </p>
          <div id="advertising-conversions" phx-update="stream" class="space-y-2">
            <div :for={{id, row} <- @streams.conversions} id={id} class="flex flex-wrap gap-3 text-sm">
              <span>{channel_label(row.channel)}</span><span>{status_label(row.status)}</span><strong>{row.count}</strong>
            </div>
          </div>
          <p class="mt-4 text-sm text-base-content/60">
            {gettext(
              "Recent delivery issues (up to 50). For an uncertain offline upload, enter its existing upload ID from Metrika to check processing without resending the sale."
            )}
          </p>
          <div id="advertising-delivery-issues" phx-update="stream" class="mt-3 space-y-3">
            <article
              :for={{id, issue} <- @streams.delivery_issues}
              id={id}
              class="rounded-xl border border-base-300 p-3 space-y-2 text-sm"
            >
              <p class="break-all">{gettext("Order")}: {issue.order_id}</p>
              <p>{channel_label(issue.channel)} · {status_label(issue.status)}</p>
              <p class="break-words">{issue.reason} · {issue.provider_status}</p>
              <.form
                :if={@can_import && issue.status == "unknown" && issue.channel == "offline"}
                for={
                  to_form(%{"conversion_id" => issue.id, "upload_id" => issue.upload_id || ""},
                    as: :reconcile
                  )
                }
                id={"reconcile-#{issue.id}"}
                phx-submit="reconcile"
                class="flex flex-wrap items-end gap-2"
              >
                <input type="hidden" name="reconcile[conversion_id]" value={issue.id} />
                <.input
                  id={"reconcile-upload-#{issue.id}"}
                  name="reconcile[upload_id]"
                  value={issue.upload_id || ""}
                  label={gettext("Existing Metrika upload ID")}
                  inputmode="numeric"
                  required
                  pattern="[0-9]{1,30}"
                />
                <button type="submit" class="btn btn-outline btn-sm">{gettext("Check existing upload")}</button>
              </.form>
            </article>
          </div>
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

  defp timestamp(nil), do: gettext("Not imported")
  defp timestamp(value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M UTC")
  defp channel_label("offline"), do: gettext("Offline goal")
  defp channel_label("purchase"), do: gettext("Product purchase")
  defp channel_label("ecommerce"), do: gettext("Product purchase")
  defp channel_label(_), do: gettext("Conversion")
  defp status_label("pending"), do: gettext("Pending")
  defp status_label("sending"), do: gettext("Sending")
  defp status_label("accepted"), do: gettext("Accepted by Yandex")
  defp status_label("submitted"), do: gettext("Accepted by Yandex; matching not confirmed")
  defp status_label("processed"), do: gettext("Processed by Yandex")
  defp status_label("unknown"), do: gettext("Delivery outcome unknown — review required")
  defp status_label("skipped"), do: gettext("Not sent")
  defp status_label("failed"), do: gettext("Delivery failed")
  defp status_label("discrepancy"), do: gettext("Order changed after delivery — review required")
  defp status_label("reverted"), do: gettext("Completion reverted — review required")
  defp status_label("stale"), do: gettext("Stopped: settings or access changed")
  defp status_label(_), do: gettext("Review required")
end
