defmodule DelivestWeb.Staff.IntegrationLive.Index do
  use DelivestWeb, :live_view

  alias Delivest.Identity
  alias Delivest.Integrations.{Crm, Dadata, Zvonok}
  alias Delivest.Integrations.Crm.BranchSettings

  on_mount {DelivestWeb.Hooks.Permission, "branches.read"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: gettext("Integrations"),
       crm: Crm.get_branch_settings(socket.assigns.current_branch.id),
       zvonok_configured: Zvonok.configured?(),
       dadata_active: Dadata.active?(),
       can_edit_shared: Identity.can?(socket.assigns.current_staff, "admin")
     )}
  end

  defp provider_status(crm, provider) do
    cond do
      BranchSettings.active_provider(crm) == provider -> :active
      Crm.configured?(crm, provider) -> :configured
      true -> :off
    end
  end

  defp provider_path(:frontpad), do: ~p"/staff/integrations/frontpad"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8 py-4 sm:p-6">
      <.page_header
        title={gettext("Integrations")}
        subtitle={gettext("External services connected to the app.")}
      />

      <section class="space-y-3">
        <div>
          <h2 class="font-bold">{gettext("All branches")}</h2>
          <p class="text-sm text-base-content/60">
            {gettext("These settings are shared by every branch.")}
          </p>
        </div>

        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <.integration_card
            id="integration-zvonok"
            title={gettext("Sign-in by phone number")}
            description={gettext("Customers confirm the phone number with a call via zvonok.com.")}
            status={if @zvonok_configured, do: :configured, else: :off}
            path={@can_edit_shared && ~p"/staff/integrations/zvonok"}
          />
          <.integration_card
            id="integration-dadata"
            title={gettext("Delivery address on the map")}
            description={gettext("Address suggestions and the map via dadata.ru.")}
            status={if @dadata_active, do: :configured, else: :off}
            path={@can_edit_shared && ~p"/staff/integrations/dadata"}
          />
        </div>
      </section>

      <section class="space-y-3">
        <div>
          <h2 class="font-bold">{gettext("Branch")} «{@current_branch.name}»</h2>
          <p class="text-sm text-base-content/60">
            {gettext("Each branch has its own settings. Switch the branch to set up another one.")}
          </p>
        </div>

        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <.integration_card
            id="integration-routes"
            title={gettext("Order routes")}
            description={gettext("Which orders go further to the CRM.")}
            status={if BranchSettings.active_provider(@crm), do: :active, else: :off}
            path={~p"/staff/integrations/routes"}
          />
          <.integration_card
            :for={{provider, name} <- Crm.providers()}
            id={"integration-#{provider}"}
            title={name}
            description={gettext("Orders to the CRM and products matching with the app menu.")}
            status={provider_status(@crm, provider)}
            path={provider_path(provider)}
          />
        </div>
      </section>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :status, :atom, required: true
  attr :path, :any, required: true

  defp integration_card(%{path: path} = assigns) when is_binary(path) do
    ~H"""
    <.link
      id={@id}
      navigate={@path}
      class="card bg-base-100 border border-base-300 hover:border-primary transition-colors"
    >
      <.card_body title={@title} description={@description} status={@status} />
    </.link>
    """
  end

  defp integration_card(assigns) do
    ~H"""
    <div id={@id} class="card bg-base-100 border border-base-300">
      <.card_body title={@title} description={@description} status={@status} />
    </div>
    """
  end

  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :status, :atom, required: true

  defp card_body(assigns) do
    ~H"""
    <div class="card-body gap-3">
      <div class="flex items-center justify-between gap-2">
        <h3 class="card-title text-base">{@title}</h3>
        <.status_badge status={@status} />
      </div>
      <p class="text-sm text-base-content/60">{@description}</p>
    </div>
    """
  end

  attr :status, :atom, required: true

  defp status_badge(%{status: :active} = assigns),
    do: ~H"""
    <span class="badge badge-success">{gettext("Orders go to CRM")}</span>
    """

  defp status_badge(%{status: :configured} = assigns),
    do: ~H"""
    <span class="badge badge-ghost">{gettext("Connected")}</span>
    """

  defp status_badge(assigns),
    do: ~H"""
    <span class="badge badge-ghost text-base-content/50">{gettext("Not connected")}</span>
    """
end
