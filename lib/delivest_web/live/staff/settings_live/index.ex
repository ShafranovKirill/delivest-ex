defmodule DelivestWeb.Staff.SettingsLive.Index do
  use DelivestWeb, :live_view

  import DelivestWeb.Staff.SettingsComponents

  alias Delivest.Identity

  @impl true
  def mount(_params, _session, socket) do
    staff = socket.assigns.current_staff

    if Identity.can?(staff, "franchise.update") or
         (Identity.can?(staff, "branches.read") and Identity.can?(staff, "branches.update")) do
      {:ok, assign(socket, page_title: gettext("Settings"))}
    else
      {:ok, redirect(socket, to: ~p"/staff/branches/select")}
    end
  end

  defp editable_branches(staff, branches) do
    if Identity.can?(staff, "branches.read") and Identity.can?(staff, "branches.update"),
      do: branches,
      else: []
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="settings-hub" class="mx-auto max-w-5xl space-y-6 py-4 sm:p-6">
      <.page_header
        title={gettext("Settings")}
        subtitle={gettext("Choose common settings or an available branch.")}
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
          :for={branch <- editable_branches(@current_staff, @staff_branches)}
          id={"settings-branch-card-#{branch.id}"}
          navigate={~p"/staff/branches/#{branch.slug}/edit"}
          icon="hero-map-pin"
          title={branch.name}
          description={gettext("Branch settings")}
        />
      </.settings_cards>
      <.link
        :if={Identity.can?(@current_staff, "branches.read")}
        id="settings-manage-branches"
        navigate={~p"/staff/branches"}
        class="link link-primary"
      >{gettext("Manage branches")}</.link>
    </div>
    """
  end
end
