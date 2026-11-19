defmodule DelivestWeb.Staff.IntegrationLive.YandexAds do
  use DelivestWeb, :live_view

  alias Delivest.Identity
  alias Delivest.Integrations.YandexAds
  alias Delivest.Integrations.YandexAds.OAuth
  alias Delivest.Integrations.YandexAds.Campaigns

  on_mount {DelivestWeb.Hooks.Permission, "admin"}

  @secrets ~w(direct_token metrika_token refresh_token measurement_token oauth_client_secret)a

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: gettext("Yandex Direct and Metrika"),
       branches: Identity.list_branch_for_staff(socket.assigns.current_staff),
       checks: nil,
       operation: nil
     )
     |> assign_settings(YandexAds.get_settings())
     |> load_management()}
  end

  @impl true
  def handle_event("validate", %{"yandex_ads" => attrs}, socket) do
    form =
      socket.assigns.settings |> YandexAds.change_settings(attrs) |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(form, as: :yandex_ads))}
  end

  def handle_event("save", %{"yandex_ads" => attrs}, socket) do
    case YandexAds.update_collection_settings(socket.assigns.current_staff, attrs) do
      {:ok, settings} ->
        {:noreply,
         socket
         |> assign_settings(settings)
         |> load_management()
         |> assign(checks: nil)
         |> put_flash(:info, gettext("Settings saved"))
         |> push_event("staff:form-saved", %{})}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :yandex_ads))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
    end
  end

  def handle_event("check", _params, socket) do
    if Identity.can?(socket.assigns.current_staff, "admin") do
      staff = socket.assigns.current_staff

      {:noreply,
       socket
       |> assign(checks: :checking)
       |> start_async(:check_connections, fn -> YandexAds.check_connections(staff) end)}
    else
      {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
    end
  end

  def handle_event("ensure_goal", _params, socket), do: run_operation(socket, :goal)

  def handle_event("ensure_funnel_goals", _params, socket),
    do: run_operation(socket, :funnel_goals)

  def handle_event("refresh_token", _params, socket), do: run_operation(socket, :refresh)

  def handle_event("register_feed", %{"branch" => branch_id}, socket),
    do: run_operation(socket, {:feed, branch_id})

  def handle_event("reconcile", %{"reconcile" => attrs}, socket) do
    case YandexAds.reconcile_delivery(
           socket.assigns.current_staff,
           attrs["conversion_id"],
           attrs["upload_id"]
         ) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_management()
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

  def handle_event("refresh_diagnostics", _params, socket),
    do: {:noreply, load_management(socket)}

  def handle_event("binding_search", %{"search" => %{"q" => query}}, socket),
    do: {:noreply, load_binding_options(socket, query)}

  def handle_event("bind_campaign", %{"binding" => attrs}, socket) do
    case Campaigns.bind(socket.assigns.current_staff, attrs["link_id"], attrs["campaign_id"]) do
      {:ok, _} ->
        {:noreply,
         socket |> load_management() |> put_flash(:info, gettext("Campaign link saved"))}

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
        {:noreply,
         socket |> load_management() |> put_flash(:info, gettext("Campaign link removed"))}

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

  defp run_operation(socket, operation) do
    if Identity.can?(socket.assigns.current_staff, "admin") and is_nil(socket.assigns.operation) do
      staff = socket.assigns.current_staff

      {:noreply,
       socket
       |> assign(operation: operation)
       |> start_async(:yandex_operation, fn ->
         case operation do
           :goal -> YandexAds.ensure_goal(staff)
           :funnel_goals -> YandexAds.ensure_funnel_goals(staff)
           :refresh -> YandexAds.refresh_connection(staff)
           {:feed, branch_id} -> YandexAds.register_branch_feed(staff, branch_id)
         end
       end)}
    else
      {:noreply, put_flash(socket, :error, gettext("Action unavailable"))}
    end
  end

  @impl true
  def handle_async(:check_connections, {:ok, checks}, socket),
    do: {:noreply, assign(socket, checks: checks)}

  def handle_async(:check_connections, {:exit, _reason}, socket),
    do:
      {:noreply, assign(socket, checks: %{direct: {:error, :failed}, metrika: {:error, :failed}})}

  def handle_async(:yandex_operation, {:ok, {:ok, _result}}, socket),
    do:
      {:noreply,
       socket
       |> assign(operation: nil)
       |> assign_settings(YandexAds.get_settings())
       |> put_flash(
         :info,
         gettext("Yandex operation completed. Check the result in your account.")
       )}

  def handle_async(:yandex_operation, _result, socket),
    do:
      {:noreply,
       socket
       |> assign(operation: nil)
       |> put_flash(
         :error,
         gettext("Yandex operation failed. Check settings and account permissions.")
       )}

  defp load_management(socket) do
    staff = socket.assigns.current_staff
    available = YandexAds.account_report_authorized?(staff)
    today = Date.utc_today()

    conversions =
      case YandexAds.report(staff, Date.add(today, -6), today) do
        {:ok, report} -> report.conversions
        _ -> []
      end

    bindings =
      case Campaigns.list(staff) do
        {:ok, result} -> result.bindings
        _ -> []
      end

    socket
    |> assign(management_available: available)
    |> stream(:conversions, conversions,
      reset: true,
      dom_id: &"conversion-#{&1.channel}-#{&1.status}"
    )
    |> stream(:delivery_issues, YandexAds.list_delivery_issues(staff), reset: true)
    |> stream(:bindings, bindings, reset: true, dom_id: &"binding-#{&1.advertising_link_id}")
    |> load_binding_options("")
  end

  defp assign_settings(socket, settings) do
    # Credentials must never become HTML input values or LiveView diffs.
    display = Enum.reduce(@secrets, settings, &Map.put(&2, &1, nil))

    assign(socket,
      settings: settings,
      saved_secrets: Map.new(@secrets, &{&1, is_binary(Map.get(settings, &1))}),
      oauth_redirect_uri: OAuth.redirect_uri(),
      form: to_form(YandexAds.change_settings(display, %{}), as: :yandex_ads)
    )
  end

  def staff_page_header(assigns) do
    ~H"""
    <.page_header back={~p"/staff/integrations"} title={gettext("Yandex Direct and Metrika")}>
      <:actions>
        <button
          type="submit"
          form="yandex-ads-settings"
          class="btn btn-primary"
          phx-disable-with={gettext("Saving...")}
        >
          {gettext("Save")}
        </button>
      </:actions>
    </.page_header>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <section class="rounded-box border border-base-300 bg-base-100 p-5 space-y-3">
        <p>
          {gettext(
            "Connect your counter and advertising account. Campaigns and budgets remain in Direct."
          )}
        </p>
        <p class="text-sm text-base-content/70">
          {gettext(
            "Collection starts when the menu opens after you enable it and approve the privacy policy. Webvisor is off."
          )}
        </p>
        <p
          :if={@settings.credential_error}
          id="yandex-credentials-unavailable"
          role="alert"
          class="text-error"
        >
          {gettext(
            "Stored credentials could not be read. Enter new values for the marked fields; affected integration streams are paused."
          )}
        </p>
        <.link navigate={~p"/staff/analytics/advertising"} class="link link-primary">{gettext(
          "Advertising analytics"
        )}</.link>
      </section>

      <.form
        for={@form}
        id="yandex-ads-settings"
        phx-change="validate"
        phx-submit="save"
        data-staff-dirty
        class="space-y-5"
      >
        <section class="rounded-box border border-base-300 bg-base-100 p-5 space-y-4">
          <h2 class="text-lg font-bold">{gettext("Collection and access")}</h2>
          <.input
            field={@form[:enabled]}
            type="checkbox"
            label={gettext("Enable Yandex integration")}
          />
          <.input
            field={@form[:branch_ids]}
            type="select"
            multiple
            options={Enum.map(@branches, &{&1.name, &1.id})}
            label={gettext("Branches")}
          />
          <.input
            field={@form[:privacy_approved]}
            type="checkbox"
            label={
              gettext(
                "I have reviewed the privacy policy and approved analytics collection for these branches"
              )
            }
          />
          <.input
            field={@form[:browser_enabled]}
            type="checkbox"
            label={gettext("Metrika: visits and funnel")}
          />
          <.input
            field={@form[:conversions_enabled]}
            type="checkbox"
            label={gettext("Send completed orders as offline conversions")}
          />
          <.input
            field={@form[:ecommerce_enabled]}
            type="checkbox"
            label={gettext("Send product events and server purchases")}
          />
          <.input
            field={@form[:feed_enabled]}
            type="checkbox"
            label={gettext("Publish product feeds")}
          />
          <.input
            field={@form[:costs_enabled]}
            type="checkbox"
            label={gettext("Import advertising costs")}
          />
          <p class="text-sm text-base-content/60">
            {gettext(
              "Platform feature permissions also apply. Re-enabling collection does not restore the disabled period."
            )}
          </p>
        </section>

        <section class="rounded-box border border-base-300 bg-base-100 p-5 space-y-4">
          <h2 class="text-lg font-bold">{gettext("Counter and account")}</h2>
          <.input
            field={@form[:counter_id]}
            label={gettext("Metrika counter ID")}
            inputmode="numeric"
          />
          <.input field={@form[:goal]} label={gettext("Completed order goal identifier")} />
          <.input
            field={@form[:client_login]}
            label={gettext("Direct advertiser login (for agency access)")}
          />
          <.input field={@form[:oauth_client_id]} label={gettext("Yandex OAuth application ID")} />
          <p id="yandex-oauth-redirect-uri" class="text-sm text-base-content/70">
            {gettext("OAuth callback URL to enter in Yandex")}: {@oauth_redirect_uri}
          </p>
          <.input field={@form[:timezone]} label={gettext("Advertising account time zone")} />
          <.input
            field={@form[:currency]}
            type="select"
            options={[{"RUB", "RUB"}]}
            label={gettext("Currency")}
          />
          <.input
            field={@form[:include_vat]}
            type="checkbox"
            label={gettext("Include VAT in advertising costs")}
          />
          <%= for {key, label} <- secret_labels() do %>
            <div>
              <.input
                field={@form[key]}
                type="password"
                value=""
                autocomplete="new-password"
                label={label}
              />
              <p
                :if={Atom.to_string(key) in @settings.credential_errors}
                id={"yandex-#{key}-replace"}
                role="alert"
                class="text-xs text-error"
              >
                {gettext("Re-enter this credential to restore access.")}
              </p>
              <p
                :if={@saved_secrets[key]}
                id={"yandex-#{key}-saved"}
                class="text-xs text-base-content/60"
              >
                {gettext("Saved. Leave blank to keep the existing credential.")}
              </p>
            </div>
          <% end %>
        </section>
      </.form>

      <section class="rounded-box border border-base-300 bg-base-100 p-5 space-y-4">
        <h2 class="text-lg font-bold">{gettext("Connection checks")}</h2>
        <a
          id="yandex-oauth-connect"
          href="/staff/integrations/yandex-ads/connect"
          class="btn btn-primary"
        >
          {gettext("Connect with Yandex")}
        </a>
        <button
          id="yandex-check"
          type="button"
          phx-click="check"
          disabled={@checks == :checking}
          class="btn btn-outline"
        >
          {if @checks == :checking,
            do: gettext("Checking..."),
            else: gettext("Check saved connection")}
        </button>
        <p :if={is_nil(@checks)} class="text-sm text-base-content/60">
          {gettext("Not checked. Saved credentials alone do not confirm access.")}
        </p>
        <dl :if={is_map(@checks)} id="yandex-check-results" class="space-y-2">
          <div :for={{provider, result} <- @checks} class="flex gap-3">
            <dt>{provider_label(provider)}</dt><dd>{check_label(result)}</dd>
          </div>
        </dl>
        <div class="flex flex-wrap gap-3">
          <button
            id="yandex-ensure-goal"
            type="button"
            phx-click="ensure_goal"
            disabled={not is_nil(@operation)}
            class="btn btn-outline"
          >
            {gettext("Find or create the completed order goal")}
          </button>
          <button
            id="yandex-refresh-token"
            type="button"
            phx-click="refresh_token"
            disabled={not is_nil(@operation)}
            class="btn btn-outline"
          >
            {gettext("Refresh OAuth access")}
          </button>
          <button
            id="yandex-ensure-funnel-goals"
            type="button"
            phx-click="ensure_funnel_goals"
            disabled={not is_nil(@operation)}
            class="btn btn-outline"
          >
            {gettext("Configure menu and checkout goals")}
          </button>
        </div>
        <p class="text-sm text-base-content/60">
          {gettext(
            "Use one completed order goal for campaign optimization. Creating the goal does not start or change campaigns."
          )}
        </p>
      </section>

      <section
        id="yandex-campaign-mappings"
        class="rounded-box border border-base-300 bg-base-100 p-5 space-y-3"
      >
        <%= if @management_available do %>
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
        :if={@management_available}
        id="yandex-delivery-diagnostics"
        class="rounded-box border border-base-300 bg-base-100 p-5"
      >
        <h2 class="mb-3 text-lg font-bold">{gettext("Conversion delivery")}</h2>
        <button
          id="yandex-refresh-diagnostics"
          type="button"
          phx-click="refresh_diagnostics"
          class="btn btn-outline btn-sm"
        >{gettext("Refresh")}</button>
        <p class="text-sm text-base-content/60">
          {gettext(
            "Delivery totals cover the last seven days. Recent issues may include earlier orders."
          )}
        </p>
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
              :if={issue.status == "unknown" && issue.channel == "offline"}
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
      <section
        :if={@settings.feed_enabled}
        id="yandex-feeds"
        class="rounded-box border border-base-300 bg-base-100 p-5 space-y-3"
      >
        <h2 class="text-lg font-bold">{gettext("Product feeds")}</h2>
        <p class="text-sm text-base-content/70">
          {gettext(
            "A feed is available only for an enabled branch with the platform feature granted. Yandex may retain a previously downloaded copy after disabling it."
          )}
        </p>
        <div :for={branch <- Enum.filter(@branches, &(&1.id in @settings.branch_ids))}>
          <a
            href={"/seo/branches/#{URI.encode(branch.slug, &URI.char_unreserved?/1)}/catalog.xml"}
            target="_blank"
            rel="noopener"
            class="link link-primary"
          >{branch.name}</a>
          <button
            type="button"
            id={"yandex-register-feed-#{branch.id}"}
            phx-click="register_feed"
            phx-value-branch={branch.id}
            disabled={not is_nil(@operation)}
            class="btn btn-outline btn-sm ml-3"
          >
            {gettext("Register feed in Direct")}
          </button>
        </div>
      </section>
    </div>
    """
  end

  defp secret_labels do
    [
      direct_token: gettext("Direct OAuth token"),
      metrika_token: gettext("Metrika OAuth token"),
      refresh_token: gettext("OAuth refresh token"),
      measurement_token: gettext("Measurement Protocol token"),
      oauth_client_secret: gettext("Yandex OAuth application secret")
    ]
  end

  defp provider_label(:direct), do: "Direct"
  defp provider_label(:metrika), do: "Metrika"
  defp provider_label(:metrika_goal), do: gettext("Completed order goal")
  defp provider_label(_), do: gettext("Connection")
  defp check_label({:ok, _}), do: gettext("Connection checked")
  defp check_label(:ok), do: gettext("Connection checked")

  defp check_label(_),
    do: gettext("Access not confirmed. Review credentials and account permissions.")

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
