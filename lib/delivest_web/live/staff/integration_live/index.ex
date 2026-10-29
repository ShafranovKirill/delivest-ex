defmodule DelivestWeb.Staff.IntegrationLive.Index do
  use DelivestWeb, :live_view

  alias Delivest.{Couriers, Identity}
  alias Delivest.Integrations.{Crm, Dadata, Health, YandexDelivery, YandexEda, Zvonok}
  alias Delivest.Integrations.Crm.BranchSettings

  on_mount {DelivestWeb.Hooks.Permission, "integrations.read"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: gettext("Integrations"),
       crm: Crm.get_branch_settings(socket.assigns.current_branch.id),
       yandex_eda: YandexEda.get_branch_settings(socket.assigns.current_branch.id),
       yandex_delivery: yandex_delivery_status(socket.assigns.current_branch.id),
       zvonok_configured: Zvonok.configured?(),
       dadata_active: Dadata.active?(),
       health: Health.for_branch(socket.assigns.current_branch.id),
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

  defp yandex_delivery_status(branch_id) do
    configured? = YandexDelivery.Settings.configured?(YandexDelivery.settings(branch_id))

    case Couriers.settings(branch_id) do
      %{source: :yandex} when configured? -> :calling
      _settings when configured? -> :configured
      _settings -> :off
    end
  end

  defp provider_path(branch, :frontpad), do: ~p"/staff/b/#{branch}/integrations/frontpad"
  defp provider_path(branch, _provider), do: ~p"/staff/b/#{branch}/integrations"

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
            path={@can_edit_shared && ~p"/staff/b/#{@current_branch}/integrations/zvonok"}
          />
          <.integration_card
            id="integration-dadata"
            title={gettext("Delivery address on the map")}
            description={gettext("Address suggestions and the map via dadata.ru.")}
            status={if @dadata_active, do: :configured, else: :off}
            path={@can_edit_shared && ~p"/staff/b/#{@current_branch}/integrations/dadata"}
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
            path={~p"/staff/b/#{@current_branch}/integrations/routes"}
          />
          <.integration_card
            id="integration-yandex-eda"
            title={gettext("Yandex Eda")}
            description={gettext("Orders from Yandex Eda and Delivery Club.")}
            status={if @yandex_eda.enabled, do: :receiving, else: :off}
            health={@health["yandex_eda"]}
            path={~p"/staff/b/#{@current_branch}/integrations/yandex-eda"}
          />
          <.integration_card
            id="integration-yandex-delivery"
            title={gettext("Yandex Delivery")}
            description={gettext("A Yandex courier for the delivery orders.")}
            status={@yandex_delivery}
            health={@health["yandex_delivery"]}
            path={~p"/staff/b/#{@current_branch}/integrations/yandex-delivery"}
          />
          <.integration_card
            :for={{provider, name} <- Crm.providers()}
            id={"integration-#{provider}"}
            title={name}
            description={gettext("Orders to the CRM and products matching with the app menu.")}
            status={provider_status(@crm, provider)}
            health={@health[to_string(provider)]}
            path={provider_path(@current_branch, provider)}
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
  attr :health, :any, default: nil
  attr :path, :any, required: true

  defp integration_card(%{path: path} = assigns) when is_binary(path) do
    ~H"""
    <.link
      id={@id}
      navigate={@path}
      class="card bg-base-100 border border-base-300 hover:border-primary transition-colors"
    >
      <.card_body title={@title} description={@description} status={@status} health={@health} />
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
  attr :health, :any, default: nil

  defp card_body(assigns) do
    ~H"""
    <div class="card-body gap-3">
      <div class="flex items-center justify-between gap-2">
        <h3 class="card-title text-base">{@title}</h3>
        <.status_badge status={@status} />
      </div>
      <p class="text-sm text-base-content/60">{@description}</p>
      <.health_badge :if={@status != :off} health={@health} />
    </div>
    """
  end

  attr :health, :any, required: true

  defp health_badge(%{health: %{status: :auth}} = assigns),
    do: ~H"""
    <span class="badge badge-error gap-1">
      <.icon name="hero-key" class="size-3" /> {gettext("Reconnect")}
    </span>
    """

  defp health_badge(%{health: %{status: :failed}} = assigns),
    do: ~H"""
    <span class="badge badge-warning gap-1">
      <.icon name="hero-exclamation-triangle" class="size-3" /> {gettext("No connection")}
    </span>
    """

  defp health_badge(assigns), do: ~H""

  attr :status, :atom, required: true

  defp status_badge(%{status: :active} = assigns),
    do: ~H"""
    <span class="badge badge-success">{gettext("Orders go to CRM")}</span>
    """

  defp status_badge(%{status: :receiving} = assigns),
    do: ~H"""
    <span class="badge badge-success">{gettext("Takes orders")}</span>
    """

  defp status_badge(%{status: :calling} = assigns),
    do: ~H"""
    <span class="badge badge-success">{gettext("Calls couriers")}</span>
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
