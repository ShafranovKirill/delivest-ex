defmodule DelivestWeb.Staff.IntegrationLive.Index do
  use DelivestWeb, :live_view

  alias Delivest.Identity
  alias Delivest.Integrations.Crm
  alias Delivest.Integrations.Crm.{BranchSettings, Catalog}
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  on_mount {DelivestWeb.Hooks.Permission, "branches.read"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: gettext("Integrations"),
       can_edit_branch: Identity.can?(socket.assigns.current_staff, "branches.update"),
       tab: :check,
       query: "",
       refresh_timer: nil
     )
     |> load_settings()}
  end

  @impl true
  def handle_params(_params, _url, %{assigns: %{live_action: :frontpad}} = socket),
    do: {:noreply, load_catalog(socket)}

  def handle_params(_params, _url, socket), do: {:noreply, socket}

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

  def handle_event("tab", %{"tab" => tab}, socket) when tab in ~w(check products),
    do: {:noreply, assign(socket, tab: String.to_existing_atom(tab))}

  def handle_event("search", %{"q" => query}, socket),
    do: {:noreply, assign(socket, query: query)}

  @impl true
  def handle_info(:refresh_available, socket),
    do: {:noreply, socket |> assign(refresh_timer: nil) |> assign_available_at()}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp load_settings(socket) do
    crm =
      case Identity.get_branch(socket.assigns.current_branch.id, preload: [:info]) do
        {:ok, %{info: %{crm: %BranchSettings{} = crm}}} -> crm
        _ -> %BranchSettings{}
      end

    assign(socket, crm: crm)
  end

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

  defp provider_status(crm, provider) do
    settings = Map.get(crm, provider)

    cond do
      BranchSettings.active_provider(crm) == provider -> :active
      settings && settings.api_key not in [nil, ""] -> :configured
      true -> :off
    end
  end

  defp provider_path(:frontpad), do: ~p"/staff/integrations/frontpad"

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
  def render(%{live_action: :index} = assigns) do
    ~H"""
    <div class="space-y-6 py-4 sm:p-6">
      <.page_header
        title={gettext("Integrations")}
        subtitle={gettext("External services connected to the current branch.")}
      />

      <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <.link
          :for={{provider, name} <- Crm.providers()}
          id={"integration-#{provider}"}
          navigate={provider_path(provider)}
          class="card bg-base-100 border border-base-300 hover:border-primary transition-colors"
        >
          <div class="card-body gap-3">
            <div class="flex items-center justify-between gap-2">
              <h2 class="card-title">{name}</h2>
              <.provider_badge status={provider_status(@crm, provider)} />
            </div>
            <p class="text-sm text-base-content/60">
              {gettext("Products in the CRM and their match with the app menu.")}
            </p>
          </div>
        </.link>
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="space-y-6 py-4 sm:p-6">
      <.link navigate={~p"/staff/integrations"} class="btn btn-ghost btn-sm -ml-2">
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

      <div :if={!api_key?(@crm)} id="frontpad-not-configured" class="alert">
        <.icon name="hero-information-circle" class="size-5" />
        <span>{gettext("Frontpad API key is not set for this branch")}</span>
        <.link
          :if={@can_edit_branch}
          navigate={~p"/staff/branches/#{@current_branch.slug}/edit"}
          class="btn btn-sm"
        >
          {gettext("Branch settings")}
        </.link>
      </div>

      <%= if @snapshot do %>
        <p class="text-sm text-base-content/60">
          {gettext("Received from Frontpad")}: {OrderHelpers.local_datetime(@snapshot.checked_at)}
        </p>

        <div role="tablist" class="tabs tabs-boxed w-fit max-w-full overflow-x-auto">
          <button
            type="button"
            role="tab"
            phx-click="tab"
            phx-value-tab="check"
            class={["tab gap-2 whitespace-nowrap", @tab == :check && "tab-active font-bold"]}
          >
            <.icon name="hero-check-badge" class="size-4" /> {gettext("Check")}
          </button>
          <button
            type="button"
            role="tab"
            phx-click="tab"
            phx-value-tab="products"
            class={["tab gap-2 whitespace-nowrap", @tab == :products && "tab-active font-bold"]}
          >
            <.icon name="hero-cube" class="size-4" />
            {gettext("Frontpad products")} ({length(@snapshot.products)})
          </button>
        </div>

        <.check_results :if={@tab == :check} issues={@issues} />
        <.crm_products
          :if={@tab == :products}
          products={filter_products(@snapshot.products, @query)}
          query={@query}
        />
      <% else %>
        <div :if={api_key?(@crm)} id="frontpad-empty" class="text-center text-base-content/60 py-10">
          {gettext("Products have not been received yet. Get them from Frontpad to check the menu.")}
        </div>
      <% end %>
    </div>
    """
  end

  attr :status, :atom, required: true

  defp provider_badge(%{status: :active} = assigns),
    do: ~H"""
    <span class="badge badge-success">{gettext("Orders go to CRM")}</span>
    """

  defp provider_badge(%{status: :configured} = assigns),
    do: ~H"""
    <span class="badge badge-ghost">{gettext("Connected")}</span>
    """

  defp provider_badge(assigns),
    do: ~H"""
    <span class="badge badge-ghost text-base-content/50">{gettext("Not connected")}</span>
    """

  attr :issues, :list, required: true

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
      />

      <.issue_list
        :if={@mismatched != []}
        id="frontpad-price-mismatch"
        title={gettext("Price differs")}
        issues={@mismatched}
      />

      <.issue_list
        :if={@unlinked != []}
        id="frontpad-unlinked"
        title={gettext("No CRM ID")}
        hint={gettext("These products are not linked to Frontpad.")}
        issues={@unlinked}
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :hint, :string, default: nil
  attr :issues, :list, required: true

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
            <.link navigate={~p"/staff/products/#{issue.product_id}/edit"} class="link link-hover">
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

      <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
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
      </div>
    </div>
    """
  end
end
