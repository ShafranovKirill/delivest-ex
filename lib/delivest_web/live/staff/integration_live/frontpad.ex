defmodule DelivestWeb.Staff.IntegrationLive.Frontpad do
  use DelivestWeb, :live_view

  alias Delivest.Identity
  alias Delivest.Integrations.Crm
  alias Delivest.Integrations.Crm.{BranchSettings, Catalog, StopSync}
  alias Delivest.Integrations.{Channels, Frontpad}
  alias DelivestWeb.Staff.IntegrationLive.JournalComponent
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  on_mount {DelivestWeb.Hooks.Permission, "integrations.read"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Frontpad",
       can_edit_branch: Identity.can?(socket.assigns.current_staff, "integrations.update"),
       query: "",
       refresh_timer: nil,
       stop_sync: StopSync.last(socket.assigns.current_branch.id)
     )
     |> load_settings()
     |> load_catalog()
     |> then(&assign(&1, tab: if(api_key?(&1.assigns.crm), do: :check, else: :settings)))}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    case Catalog.refresh(socket.assigns.current_branch.id, :frontpad) do
      {:ok, _snapshot} ->
        {:noreply,
         socket |> load_catalog() |> put_flash(:info, gettext("Products received from Frontpad"))}

      {:error, {:too_early, _available_at}} ->
        {:noreply, socket |> load_catalog() |> put_flash(:error, gettext("Too early to update"))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, refresh_error(reason))}
    end
  end

  def handle_event("sync_stops", _params, socket) do
    case StopSync.sync(socket.assigns.current_branch.id) do
      {:ok, :disabled} ->
        {:noreply,
         socket |> assign(stop_sync: nil) |> put_flash(:info, gettext("Stop list sync is off"))}

      {:ok, result} ->
        {:noreply,
         socket |> assign(stop_sync: result) |> put_flash(:info, gettext("Stop list updated"))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, refresh_error(reason))}
    end
  end

  def handle_event("tab", %{"tab" => tab}, socket)
      when tab in ~w(settings check products journal),
      do: {:noreply, assign(socket, tab: String.to_existing_atom(tab))}

  def handle_event("search", %{"q" => query}, socket),
    do: {:noreply, assign(socket, query: query)}

  def handle_event("validate", %{"crm" => params}, socket) do
    changeset =
      socket.assigns.crm
      |> Crm.change_branch_settings(settings_params(params))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: "crm"))}
  end

  def handle_event("save", %{"crm" => params}, socket) do
    case Crm.update_branch_settings(
           socket.assigns.current_staff,
           socket.assigns.current_branch.id,
           settings_params(params)
         ) do
      {:ok, crm} ->
        {:noreply,
         socket
         |> assign_settings(crm)
         |> put_flash(:info, gettext("Settings saved"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(Map.put(changeset, :action, :update), as: "crm"))}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, gettext("Permission denied"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Please check the highlighted fields"))}
    end
  end

  @impl true
  def handle_info(:refresh_available, socket),
    do: {:noreply, socket |> assign(refresh_timer: nil) |> assign_available_at()}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp load_settings(socket),
    do: assign_settings(socket, Crm.get_branch_settings(socket.assigns.current_branch.id))

  defp assign_settings(socket, crm) do
    crm = prefill(crm)
    assign(socket, crm: crm, form: to_form(Crm.change_branch_settings(crm), as: "crm"))
  end

  defp prefill(%BranchSettings{} = crm),
    do: %{crm | provider: :frontpad, frontpad: prefill_frontpad(crm.frontpad)}

  defp prefill_frontpad(nil), do: prefill_frontpad(%Frontpad.Settings{})

  defp prefill_frontpad(%Frontpad.Settings{} = settings),
    do: %{
      settings
      | statuses: settings.statuses || %Frontpad.StatusCodes{},
        payments: settings.payments || %Frontpad.PaymentCodes{},
        tags: settings.tags || %Frontpad.TagCodes{}
    }

  defp settings_params(params), do: Map.put(params, "provider", "frontpad")

  defp load_catalog(socket) do
    branch_id = socket.assigns.current_branch.id
    snapshot = Catalog.get_snapshot(branch_id, :frontpad)

    socket
    |> assign(snapshot: snapshot, issues: Catalog.issues(branch_id, snapshot))
    |> assign_available_at()
  end

  defp assign_available_at(socket) do
    available_at = Catalog.refresh_available_at(socket.assigns.snapshot)
    wait_ms = if available_at, do: DateTime.diff(available_at, DateTime.utc_now(), :millisecond)

    if socket.assigns.refresh_timer, do: Process.cancel_timer(socket.assigns.refresh_timer)

    if wait_ms && wait_ms > 0 do
      timer = Process.send_after(self(), :refresh_available, wait_ms)
      assign(socket, available_at: available_at, refresh_timer: timer)
    else
      assign(socket, available_at: nil, refresh_timer: nil)
    end
  end

  defp refresh_error(:missing_api_key), do: gettext("Frontpad API key is not set for this branch")

  defp refresh_error(:missing_settings),
    do: gettext("Frontpad API key is not set for this branch")

  defp refresh_error({:frontpad, error}), do: gettext("Frontpad error: %{error}", error: error)
  defp refresh_error(_reason), do: gettext("Frontpad did not respond, try again later")

  defp mark_label(:paid_online), do: gettext("Paid online")
  defp mark_label(:app), do: gettext("App")
  defp mark_label(:staff), do: gettext("Admin")
  defp mark_label(source), do: Channels.name(source)

  defp api_key?(crm), do: crm.frontpad && crm.frontpad.api_key not in [nil, ""]

  defp issues_of(issues, type), do: Enum.filter(issues, &(&1.type == type))

  defp filter_products(products, ""), do: products

  defp filter_products(products, query) do
    query = String.downcase(String.trim(query))

    Enum.filter(products, fn product ->
      String.contains?(String.downcase(product["name"] || ""), query) or
        String.contains?(product["external_id"] || "", query)
    end)
  end

  defp seconds_left(available_at), do: max(DateTime.diff(available_at, DateTime.utc_now()), 0)

  defp countdown(seconds),
    do:
      "#{div(seconds, 60)}:#{seconds |> rem(60) |> Integer.to_string() |> String.pad_leading(2, "0")}"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 py-4 sm:p-6">
      <.link
        navigate={~p"/staff/b/#{@current_branch}/integrations"}
        class="btn btn-ghost btn-sm -ml-2"
      >
        <.icon name="hero-arrow-left" class="size-4" /> {gettext("Integrations")}
      </.link>

      <.page_header
        title="Frontpad"
        subtitle={gettext("Products in Frontpad and their match with the app menu.")}
      >
        <:actions :if={api_key?(@crm)}>
          <button
            :if={is_nil(@available_at)}
            id="frontpad-refresh"
            type="button"
            class="btn btn-primary"
            phx-click="refresh"
            phx-disable-with={gettext("Loading...")}
          >
            <.icon name="hero-arrow-path" class="size-4" /> {gettext("Get products")}
          </button>
          <button :if={@available_at} id="frontpad-refresh" type="button" class="btn" disabled>
            <.icon name="hero-clock" class="size-4" />
            {gettext("Available in")}
            <span
              id="frontpad-countdown"
              phx-hook=".Countdown"
              data-until={DateTime.to_iso8601(@available_at)}
              class="tabular-nums"
            >
              {countdown(seconds_left(@available_at))}
            </span>
          </button>
        </:actions>
      </.page_header>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".Countdown">
        export default {
          mounted() {
            this.tick()
            this.timer = setInterval(() => this.tick(), 1000)
          },
          updated() {
            this.tick()
          },
          destroyed() {
            clearInterval(this.timer)
          },
          tick() {
            const left = Math.max(0, Math.round((Date.parse(this.el.dataset.until) - Date.now()) / 1000))
            this.el.textContent = `${Math.floor(left / 60)}:${String(left % 60).padStart(2, "0")}`
          }
        }
      </script>

      <div role="tablist" class="tabs tabs-boxed w-fit max-w-full overflow-x-auto">
        <.tab_button tab={:settings} current={@tab} icon="hero-cog-6-tooth">
          {gettext("Settings")}
        </.tab_button>
        <.tab_button tab={:check} current={@tab} icon="hero-check-badge">
          {gettext("Check")}
        </.tab_button>
        <.tab_button tab={:products} current={@tab} icon="hero-cube">
          {gettext("Frontpad products")}
          <span :if={@snapshot}>({length(@snapshot.products)})</span>
        </.tab_button>
        <.tab_button tab={:journal} current={@tab} icon="hero-queue-list">
          {gettext("Request journal")}
        </.tab_button>
      </div>

      <.guide :if={@tab == :settings} crm={@crm} branch={@current_branch} />

      <.settings_form
        :if={@tab == :settings}
        form={@form}
        crm={@crm}
        can_edit={@can_edit_branch}
      />

      <.stop_sync_panel
        :if={@tab == :settings and @crm.frontpad.sync_stops}
        result={@stop_sync}
        can_edit={@can_edit_branch}
      />

      <div
        :if={@tab in [:check, :products] and !api_key?(@crm)}
        id="frontpad-not-configured"
        class="alert"
      >
        <.icon name="hero-information-circle" class="size-5" />
        <span>{gettext("Frontpad API key is not set for this branch")}</span>
        <button type="button" class="btn btn-sm" phx-click="tab" phx-value-tab="settings">
          {gettext("Settings")}
        </button>
      </div>

      <.live_component
        :if={@tab == :journal}
        module={JournalComponent}
        id="frontpad-journal"
        provider={:frontpad}
        branch_id={@current_branch.id}
      />

      <%= if @tab in [:check, :products] and api_key?(@crm) do %>
        <%= if @snapshot do %>
          <p class="text-sm text-base-content/60">
            {gettext("Received from Frontpad")}: {OrderHelpers.local_datetime(@snapshot.checked_at)}
          </p>

          <.check_results :if={@tab == :check} issues={@issues} branch={@current_branch} />
          <.crm_products
            :if={@tab == :products}
            products={filter_products(@snapshot.products, @query)}
            query={@query}
          />
        <% else %>
          <div id="frontpad-empty" class="text-center text-base-content/60 py-10">
            {gettext("Products have not been received yet. Get them from Frontpad to check the menu.")}
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :tab, :atom, required: true
  attr :current, :atom, required: true
  attr :icon, :string, required: true
  slot :inner_block, required: true

  defp tab_button(assigns) do
    ~H"""
    <button
      type="button"
      role="tab"
      phx-click="tab"
      phx-value-tab={@tab}
      class={["tab gap-2 whitespace-nowrap", @tab == @current && "tab-active font-bold"]}
    >
      <.icon name={@icon} class="size-4" /> {render_slot(@inner_block)}
    </button>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :crm, BranchSettings, required: true
  attr :can_edit, :boolean, required: true

  defp settings_form(assigns) do
    ~H"""
    <.form
      for={@form}
      id="frontpad-settings"
      phx-change="validate"
      phx-submit="save"
      class="rounded-box border border-base-300 bg-base-100 p-5 sm:p-6"
    >
      <fieldset disabled={!@can_edit} class="space-y-4">
        <.input field={@form[:enabled]} type="checkbox" label={gettext("Send orders to Frontpad")} />

        <.inputs_for :let={frontpad} field={@form[:frontpad]}>
          <div class="grid gap-4 sm:grid-cols-2">
            <.input
              field={frontpad[:api_key]}
              type="password"
              value={frontpad[:api_key].value}
              label={gettext("Frontpad API Key")}
            />
            <.input field={frontpad[:affiliate]} type="text" label={gettext("Frontpad Branch ID")} />
          </div>

          <div class="space-y-1">
            <.input
              field={frontpad[:price_override]}
              type="checkbox"
              label={gettext("Send discounted prices to Frontpad")}
            />
            <p class="text-xs text-base-content/60">
              {gettext(
                "Enable only when «price change on order» is turned on for products in Frontpad. Otherwise the order discount is sent as a single amount."
              )}
            </p>
          </div>

          <div class="space-y-1">
            <.input
              field={frontpad[:delivery_article]}
              type="text"
              inputmode="numeric"
              label={gettext("Delivery article")}
            />
            <p class="text-xs text-base-content/60">
              {gettext(
                "Article of the «Delivery» product in Frontpad with «price change on order» turned on. The delivery price goes as its line. Without it the price is written into the order note."
              )}
            </p>
          </div>

          <div class="space-y-1">
            <.input
              field={frontpad[:sync_stops]}
              type="checkbox"
              label={gettext("Take the stop list from Frontpad")}
            />
            <p class="text-xs text-base-content/60">
              {gettext(
                "Every 10 minutes products from the Frontpad stop list become unavailable in the app. They are lifted in Frontpad."
              )}
            </p>
          </div>

          <div class="space-y-2">
            <p class="text-sm font-medium">{gettext("Frontpad status codes")}</p>
            <p class="text-xs text-base-content/60">
              {gettext(
                "Codes from the Frontpad status reference. Customers see the matching status of their order."
              )}
            </p>
            <.inputs_for :let={codes} field={frontpad[:statuses]}>
              <div class="grid grid-cols-2 gap-2 sm:grid-cols-6">
                <.input
                  :for={status <- Frontpad.StatusCodes.statuses()}
                  field={codes[status]}
                  type="text"
                  inputmode="numeric"
                  label={OrderHelpers.status_label(status)}
                />
              </div>
            </.inputs_for>
            <p class="text-xs text-base-content/60">
              {gettext(
                "Frontpad reports at most %{count} statuses per order. If all are filled, «Confirmed» is not reported: the app marks the order confirmed once Frontpad takes it.",
                count: Frontpad.StatusCodes.hook_limit()
              )}
            </p>
          </div>

          <div id="frontpad-payments" class="space-y-2">
            <p class="text-sm font-medium">{gettext("Frontpad payment codes")}</p>
            <p class="text-xs text-base-content/60">
              {gettext(
                "Codes from the Frontpad «Payment options» reference. Empty: cash is 1, card is 2, online payment goes as card."
              )}
            </p>
            <.inputs_for :let={codes} field={frontpad[:payments]}>
              <div class="grid grid-cols-2 gap-2 sm:grid-cols-6">
                <.input
                  :for={method <- Frontpad.PaymentCodes.methods()}
                  field={codes[method]}
                  type="text"
                  inputmode="numeric"
                  placeholder={Frontpad.PaymentCodes.default(method)}
                  label={OrderHelpers.payment_label(method)}
                />
              </div>
            </.inputs_for>
          </div>

          <div id="frontpad-tags" class="space-y-2">
            <p class="text-sm font-medium">{gettext("Frontpad order marks")}</p>
            <p class="text-xs text-base-content/60">
              {gettext(
                "Codes from the Frontpad «Order marks» reference. The order gets the mark of its source and, if paid online, the paid mark. Leave empty to send no mark."
              )}
            </p>
            <.inputs_for :let={codes} field={frontpad[:tags]}>
              <div class="grid grid-cols-2 gap-2 sm:grid-cols-6">
                <.input
                  :for={mark <- Frontpad.TagCodes.marks()}
                  field={codes[mark]}
                  type="text"
                  inputmode="numeric"
                  label={mark_label(mark)}
                />
              </div>
            </.inputs_for>
          </div>
        </.inputs_for>

        <div :if={@crm.frontpad.webhook_token} id="frontpad-webhook" class="space-y-1">
          <p class="text-sm font-medium">{gettext("Webhook URL for Frontpad API settings")}</p>
          <code class="block break-all rounded bg-base-200 p-2 text-xs">
            {Frontpad.webhook_url(@crm.frontpad.webhook_token)}
          </code>
        </div>

        <div :if={@can_edit} class="flex justify-end">
          <button type="submit" class="btn btn-primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save")}
          </button>
        </div>
      </fieldset>
    </.form>
    """
  end

  attr :crm, BranchSettings, required: true
  attr :branch, :map, required: true

  defp guide(assigns) do
    ~H"""
    <details
      id="frontpad-guide"
      class="group rounded-box border border-base-300 bg-base-100"
      open={!api_key?(@crm)}
    >
      <summary class="flex cursor-pointer items-center gap-2 p-4 font-bold sm:px-6">
        <.icon name="hero-book-open" class="size-5 text-primary" />
        {gettext("How to connect Frontpad")}
        <.icon
          name="hero-chevron-down"
          class="ml-auto size-4 transition-transform group-open:rotate-180"
        />
      </summary>
      <ol class="list-decimal space-y-3 px-4 pb-5 pl-10 text-sm sm:px-6 sm:pl-12">
        <li>
          {gettext(
            "Frontpad: «Settings» → «General» → turn the API on. Copy the secret into «Frontpad API Key» below."
          )}
        </li>
        <li>
          {gettext(
            "If Frontpad has several branches, put the code of this one into «Frontpad Branch ID»."
          )}
        </li>
        <li>
          {gettext(
            "Give every product sold in the app a unique numeric article in Frontpad and enter it in the product card of the app, field «Frontpad ID». The «Check» tab shows what is missing."
          )}
        </li>
        <li>
          {gettext(
            "Reference «Order statuses»: you need statuses for preparing, ready, on the way, completed and cancelled. Enter their API codes in «Frontpad status codes»."
          )}
        </li>
        <li>
          {gettext(
            "Reference «Payment options»: create «Cash», «Card on delivery» and «Paid online». Enter their API codes in «Frontpad payment codes»."
          )}
        </li>
        <li>
          {gettext(
            "Reference «Order marks»: create «App», «Admin», «Yandex Eda» and «Paid online». Enter their API codes in «Frontpad order marks», so the cashier sees where the order came from."
          )}
        </li>
        <li>
          {gettext(
            "Save the settings, copy the webhook URL below into the Frontpad API settings and restart the Frontpad program. Without it order statuses do not come back."
          )}
        </li>
        <li>
          {gettext(
            "Turn on «Send orders to Frontpad». On the «Order routes» page choose which sources go to Frontpad: the app and the admin by default, Yandex Eda only if it is not connected to Frontpad directly."
          )}
          <.link
            navigate={~p"/staff/b/#{@branch}/integrations/routes"}
            class="link link-primary"
          >
            {gettext("Order routes")}
          </.link>
        </li>
        <li>
          {gettext(
            "Optional: «Take the stop list from Frontpad» to hide products stopped in Frontpad from the app and Yandex Eda."
          )}
        </li>
        <li>
          {gettext(
            "Place a test order in the app: it should appear in Frontpad with the right payment and mark, and its status should change here when changed in Frontpad."
          )}
        </li>
      </ol>
    </details>
    """
  end

  attr :result, :map, default: nil
  attr :can_edit, :boolean, required: true

  defp stop_sync_panel(assigns) do
    ~H"""
    <section id="frontpad-stops" class="card bg-base-100 border border-base-300">
      <div class="card-body gap-3 p-4 sm:p-6">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <div>
            <h2 class="font-bold">{gettext("Stop list from Frontpad")}</h2>
            <p :if={@result} class="text-sm text-base-content/60">
              {gettext("Updated %{time}, products in stop: %{count}",
                time: OrderHelpers.local_datetime(@result.synced_at),
                count: @result.stopped
              )}
            </p>
            <p :if={is_nil(@result)} class="text-sm text-base-content/60">
              {gettext("Not received yet")}
            </p>
          </div>
          <button
            :if={@can_edit}
            id="frontpad-sync-stops"
            type="button"
            class="btn btn-sm"
            phx-click="sync_stops"
            phx-disable-with={gettext("Loading...")}
          >
            <.icon name="hero-arrow-path" class="size-4" /> {gettext("Update now")}
          </button>
        </div>

        <div :if={@result && @result.unlinked != []} id="frontpad-stops-unlinked" class="text-sm">
          <p class="font-medium">{gettext("In the Frontpad stop list but not linked to products")}</p>
          <p class="text-base-content/60">{Enum.join(@result.unlinked, ", ")}</p>
        </div>
      </div>
    </section>
    """
  end

  attr :issues, :list, required: true
  attr :branch, :map, required: true

  defp check_results(assigns) do
    assigns =
      assign(assigns,
        missing: issues_of(assigns.issues, :missing_in_crm),
        mismatched: issues_of(assigns.issues, :price_mismatch),
        unlinked: issues_of(assigns.issues, :missing_crm_id)
      )

    ~H"""
    <div id="frontpad-check" class="space-y-4">
      <div
        :if={@missing == [] and @mismatched == []}
        id="frontpad-check-ok"
        class="alert alert-success"
      >
        <.icon name="hero-check-circle" class="size-5" />
        <span>{gettext("All products with a CRM ID are found in Frontpad.")}</span>
      </div>

      <.issue_list
        :if={@missing != []}
        id="frontpad-missing"
        title={gettext("Not found in Frontpad")}
        hint={gettext("Orders with these products will not reach Frontpad.")}
        issues={@missing}
        branch={@branch}
      />

      <.issue_list
        :if={@mismatched != []}
        id="frontpad-price-mismatch"
        title={gettext("Price differs")}
        issues={@mismatched}
        branch={@branch}
      />

      <.issue_list
        :if={@unlinked != []}
        id="frontpad-unlinked"
        title={gettext("No CRM ID")}
        hint={gettext("These products are not linked to Frontpad.")}
        issues={@unlinked}
        branch={@branch}
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :hint, :string, default: nil
  attr :issues, :list, required: true
  attr :branch, :map, required: true

  defp issue_list(assigns) do
    ~H"""
    <section id={@id} class="card bg-base-100 border border-base-300">
      <div class="card-body gap-3 p-4 sm:p-6">
        <div>
          <h2 class="font-bold">{@title} ({length(@issues)})</h2>
          <p :if={@hint} class="text-sm text-base-content/60">{@hint}</p>
        </div>
        <ul class="divide-y divide-base-300">
          <li
            :for={issue <- @issues}
            class="flex flex-wrap items-center justify-between gap-2 py-2 text-sm"
          >
            <.link
              navigate={~p"/staff/b/#{@branch}/products/#{issue.product_id}/edit"}
              class="link link-hover"
            >
              {issue.name}
            </.link>
            <span class="flex items-center gap-3 text-base-content/60">
              <span :if={issue.external_id not in [nil, ""]}>CRM ID {issue.external_id}</span>
              <span :if={issue.type == :price_mismatch} class="tabular-nums">
                {OrderHelpers.money(issue.app_price)} → {OrderHelpers.money(issue.crm_price)}
              </span>
            </span>
          </li>
        </ul>
      </div>
    </section>
    """
  end

  attr :products, :list, required: true
  attr :query, :string, required: true

  defp crm_products(assigns) do
    ~H"""
    <div class="space-y-3">
      <form id="frontpad-search" phx-change="search" phx-submit="search">
        <input
          type="text"
          name="q"
          value={@query}
          placeholder={gettext("Search by name or CRM ID...")}
          class="input input-bordered w-full sm:max-w-sm"
          phx-debounce="300"
        />
      </form>

      <.card class="overflow-x-auto">
        <table id="frontpad-products" class="table">
          <thead>
            <tr>
              <th>CRM ID</th>
              <th>{gettext("Name")}</th>
              <th class="text-right">{gettext("Price")}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={product <- @products}>
              <td class="tabular-nums">{product["external_id"]}</td>
              <td>{product["name"]}</td>
              <td class="text-right tabular-nums">{OrderHelpers.money(product["price"])}</td>
            </tr>
            <tr :if={@products == []}>
              <td colspan="3" class="text-center text-base-content/60">{gettext("Nothing found")}</td>
            </tr>
          </tbody>
        </table>
      </.card>
    </div>
    """
  end
end
