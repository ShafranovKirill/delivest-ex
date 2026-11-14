defmodule DelivestWeb.Staff.SettingsComponents do
  use DelivestWeb, :html

  import DelivestWeb.CoreComponents, only: [icon: 1]

  attr :staff, :any, required: true
  attr :branches, :list, required: true
  attr :selected, :any, default: nil
  attr :current_path, :string, default: nil
  attr :scope_branch, :any, default: nil
  attr :return_source, :string, default: nil
  attr :variant, :atom, default: :horizontal, values: [:horizontal, :sidebar]

  def settings_navigation(assigns) do
    branch = Enum.find(assigns.branches, &(&1.id == assigns.selected))

    path =
      assigns.current_path ||
        if(branch, do: "/staff/branches/#{branch.slug}/edit", else: "/staff/franchise")

    assigns =
      assign(assigns,
        entries:
          DelivestWeb.StaffNav.settings_entries(assigns.staff, branch)
          |> Enum.reject(&(&1.id == :settings)),
        active_id: DelivestWeb.StaffNav.active_setting(path)
      )

    ~H"""
    <nav
      id="settings-navigation"
      phx-hook="ActiveSectionNav"
      class={[
        "flex gap-2 rounded-box border border-base-300 bg-base-100 p-2",
        @variant == :sidebar &&
          "min-w-0 max-w-full self-start overflow-x-auto lg:w-full lg:flex-col lg:items-stretch lg:overflow-visible",
        @variant == :horizontal && "flex-wrap items-center"
      ]}
      aria-label={gettext("Settings")}
    >
      <.link
        :for={entry <- @entries}
        id={"settings-nav-#{entry.id}"}
        navigate={
          DelivestWeb.StaffBranchPath.contextual_navigation_path(
            entry.path,
            @scope_branch,
            @return_source
          )
        }
        class={[
          "btn btn-sm btn-ghost shrink-0",
          @variant == :sidebar && "lg:justify-start",
          entry.id == @active_id && "btn-active"
        ]}
        aria-current={entry.id == @active_id && "page"}
      >{entry.label}</.link>
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
