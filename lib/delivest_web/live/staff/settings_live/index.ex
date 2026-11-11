defmodule DelivestWeb.Staff.SettingsLive.Index do
  use DelivestWeb, :live_view

  import DelivestWeb.Staff.SettingsComponents

  alias Delivest.Identity

  @impl true
  def mount(_params, _session, socket) do
    staff = socket.assigns.current_staff

    if Enum.any?(
         ~w(franchise.update branches.read delivery.read integrations.read),
         &Identity.can?(staff, &1)
       ) do
      {:ok, assign(socket, page_title: gettext("Settings"))}
    else
      {:ok, redirect(socket, to: ~p"/staff/branches/select")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="settings-hub" class="mx-auto max-w-5xl space-y-6 py-4 sm:p-6">
      <.page_header
        title={gettext("Settings")}
        subtitle={gettext("Choose the settings area.")}
      />
      <.settings_cards>
        <.settings_card
          :if={Identity.can?(@current_staff, "franchise.update")}
          id="settings-common-card"
          navigate={~p"/staff/franchise"}
          icon="hero-building-storefront"
          title={gettext("Common settings")}
          description={
            gettext("Name, brand color, seller details and legal documents for all branches.")
          }
        />
        <.settings_card
          :if={
            Identity.can?(@current_staff, "branches.read") or
              Identity.can?(@current_staff, "delivery.read")
          }
          id="settings-branches-card"
          navigate={~p"/staff/branches"}
          icon="hero-map-pin"
          title={gettext("Settings for branches")}
          description={gettext("Choose a branch to manage its settings and delivery.")}
        />
        <.settings_card
          :if={Identity.can?(@current_staff, "integrations.read")}
          id="settings-integrations-card"
          navigate={~p"/staff/integrations"}
          icon="hero-puzzle-piece"
          title={gettext("Integrations")}
          description={gettext("External services connected to the app.")}
        />
      </.settings_cards>
    </div>
    """
  end
end
