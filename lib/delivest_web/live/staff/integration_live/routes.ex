defmodule DelivestWeb.Staff.IntegrationLive.Routes do
  use DelivestWeb, :live_view

  alias Delivest.Identity
  alias Delivest.Integrations.{Channels, Crm}
  alias Delivest.Integrations.Crm.BranchSettings
  alias Delivest.Oms.{OrderSource, SourceStats}

  on_mount {DelivestWeb.Hooks.Permission, "branches.read"}

  @impl true
  def mount(_params, _session, socket) do
    branch_id = socket.assigns.current_branch.id

    {:ok,
     socket
     |> assign(
       page_title: gettext("Order routes"),
       can_edit: Identity.can?(socket.assigns.current_staff, "branches.update"),
       stats: SourceStats.today(branch_id)
     )
     |> assign_crm(Crm.get_branch_settings(branch_id))}
  end

  @impl true
  def handle_event("toggle", %{"source" => source}, socket) do
    sources = toggle(socket.assigns.crm.sources || [], source)

    case Crm.update_branch_settings(
           socket.assigns.current_staff,
           socket.assigns.current_branch.id,
           %{"sources" => sources}
         ) do
      {:ok, crm} -> {:noreply, assign_crm(socket, crm)}
      {:error, :forbidden} -> {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
      {:error, _reason} -> {:noreply, put_flash(socket, :error, gettext("Failed to save"))}
    end
  end

  defp toggle(sources, source) do
    if source in sources, do: List.delete(sources, source), else: sources ++ [source]
  end

  defp assign_crm(socket, crm) do
    provider = BranchSettings.active_provider(crm)

    assign(socket,
      crm: crm,
      provider: provider,
      provider_name: provider && Crm.provider_name(provider)
    )
  end

  defp source_label("app"), do: gettext("App")
  defp source_label("staff"), do: gettext("Admin")
  defp source_label(source), do: Channels.name(source)

  defp source_icon("app"), do: "hero-device-phone-mobile"
  defp source_icon("staff"), do: "hero-computer-desktop"
  defp source_icon(_source), do: "hero-shopping-bag"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 py-4 sm:p-6">
      <.link navigate={~p"/staff/integrations"} class="btn btn-ghost btn-sm -ml-2">
        <.icon name="hero-arrow-left" class="size-4" /> {gettext("Integrations")}
      </.link>

      <.page_header
        title={gettext("Order routes")}
        subtitle={gettext("Where orders come from and which of them go further to the CRM.")}
      />

      <div :if={is_nil(@provider)} id="routes-no-crm" class="alert">
        <.icon name="hero-information-circle" class="size-5" />
        <span>{gettext("No CRM is connected to this branch. All orders stay in the app.")}</span>
      </div>

      <div class="grid gap-3 lg:grid-cols-[1fr_8rem_1fr] lg:items-stretch">
        <%= for source <- OrderSource.all() do %>
          <.source_card
            source={source}
            label={source_label(source)}
            icon={source_icon(source)}
            stats={Map.get(@stats, source, %{orders: 0, failed: 0})}
          />
          <.route_link
            source={source}
            on={@provider && source in (@crm.sources || [])}
            enabled={@can_edit and not is_nil(@provider)}
            provider_name={@provider_name}
          />
        <% end %>
        <div
          class="order-last lg:order-none lg:col-start-3 lg:[grid-row:1/span_var(--rows)]"
          style={"--rows: #{length(OrderSource.all())}"}
        >
          <.crm_card provider_name={@provider_name} />
        </div>
      </div>
    </div>
    """
  end

  attr :source, :string, required: true
  attr :label, :string, required: true
  attr :icon, :string, required: true
  attr :stats, :map, required: true

  defp source_card(assigns) do
    ~H"""
    <div
      id={"route-source-#{@source}"}
      class="card bg-base-100 border border-base-300 lg:col-start-1"
    >
      <div class="card-body flex-row items-center gap-3 p-4">
        <span class="grid size-10 place-items-center rounded-box bg-base-200">
          <.icon name={@icon} class="size-5" />
        </span>
        <div class="min-w-0 flex-1">
          <p class="font-bold">{@label}</p>
          <p class="text-sm text-base-content/60">
            {gettext("Today: %{count}", count: @stats.orders)}
            <span :if={@stats.failed > 0} class="text-error">
              · {gettext("errors: %{count}", count: @stats.failed)}
            </span>
          </p>
        </div>
      </div>
    </div>
    """
  end

  attr :source, :string, required: true
  attr :on, :boolean, required: true
  attr :enabled, :boolean, required: true
  attr :provider_name, :string, default: nil

  defp route_link(assigns) do
    ~H"""
    <div class="flex items-center gap-2 px-2 lg:col-start-2 lg:px-0">
      <span class={[
        "hidden h-0 flex-1 border-t-2 lg:block",
        if(@on, do: "border-primary", else: "border-dashed border-base-300")
      ]} />
      <label class="flex items-center gap-2 text-sm lg:flex-col lg:gap-1">
        <input
          id={"route-toggle-#{@source}"}
          type="checkbox"
          class="toggle toggle-primary toggle-sm"
          checked={@on}
          disabled={not @enabled}
          phx-click="toggle"
          phx-value-source={@source}
        />
        <span class="lg:hidden">
          {if @provider_name, do: gettext("Send to %{crm}", crm: @provider_name)}
        </span>
      </label>
      <span class={[
        "hidden h-0 flex-1 border-t-2 lg:block",
        if(@on, do: "border-primary", else: "border-dashed border-base-300")
      ]} />
    </div>
    """
  end

  attr :provider_name, :string, default: nil

  defp crm_card(assigns) do
    ~H"""
    <div id="route-crm" class="card h-full bg-base-100 border border-base-300">
      <div class="card-body items-center justify-center gap-2 p-4 text-center">
        <.icon name="hero-server-stack" class="size-8 text-base-content/60" />
        <p class="font-bold">{@provider_name || gettext("No CRM")}</p>
        <p class="text-sm text-base-content/60">
          {if @provider_name,
            do: gettext("Orders are sent here"),
            else: gettext("Connect a CRM in integrations")}
        </p>
      </div>
    </div>
    """
  end
end
