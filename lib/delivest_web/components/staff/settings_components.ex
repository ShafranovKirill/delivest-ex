defmodule DelivestWeb.Staff.SettingsComponents do
  use DelivestWeb, :html

  import DelivestWeb.CoreComponents, only: [icon: 1]

  alias Delivest.Identity

  attr :staff, :any, required: true
  attr :branches, :list, required: true
  attr :selected, :any, default: nil

  def settings_navigation(assigns) do
    branches =
      if Identity.can?(assigns.staff, "branches.read") and
           Identity.can?(assigns.staff, "branches.update") do
        assigns.branches
      else
        []
      end

    assigns = assign(assigns, :editable_branches, branches)

    ~H"""
    <nav
      id="settings-navigation"
      class="flex flex-wrap items-center gap-2"
      aria-label={gettext("Settings")}
    >
      <.link navigate={~p"/staff/settings"} class="btn btn-sm btn-ghost">{gettext("Settings")}</.link>
      <.link
        :if={Identity.can?(@staff, "franchise.update")}
        id="settings-common"
        navigate={~p"/staff/franchise"}
        class={["btn btn-sm", @selected == :common && "btn-primary"]}
      >{gettext("Common settings")}</.link>
      <.link
        :for={branch <- @editable_branches}
        id={"settings-branch-#{branch.id}"}
        navigate={~p"/staff/branches/#{branch.slug}/edit"}
        class={["btn btn-sm", @selected == branch.id && "btn-primary"]}
      >{branch.name}</.link>
    </nav>
    """
  end

  slot :inner_block, required: true

  def settings_cards(assigns) do
    ~H"""
    <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :id, :string, required: true
  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, default: nil

  def settings_card(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={@navigate}
      class="card bg-base-100 border border-base-300 hover:border-primary transition-colors"
    >
      <div class="card-body flex-row items-start gap-3">
        <div class="bg-primary/10 text-primary rounded-field p-2 shrink-0">
          <.icon name={@icon} class="size-5" />
        </div>
        <div class="min-w-0 space-y-1">
          <h3 class="font-bold">{@title}</h3>
          <p :if={@description} class="text-sm text-base-content/60">{@description}</p>
        </div>
      </div>
    </.link>
    """
  end
end
