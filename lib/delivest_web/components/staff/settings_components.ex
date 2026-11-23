defmodule DelivestWeb.Staff.SettingsComponents do
  use DelivestWeb, :html

  import DelivestWeb.CoreComponents, only: [icon: 1]
  alias DelivestWeb.Staff.SubsectionNavigation

  attr :staff, :any, required: true
  attr :branches, :list, required: true
  attr :selected, :any, default: nil
  attr :current_path, :string, default: nil
  attr :scope_branch, :any, default: nil
  attr :return_source, :string, default: nil
  attr :variant, :atom, default: :horizontal, values: [:horizontal, :sidebar]
  attr :id_prefix, :string, default: ""

  def settings_navigation(assigns) do
    branch = Enum.find(assigns.branches, &(&1.id == assigns.selected))

    path =
      assigns.current_path ||
        if(branch, do: "/staff/branches/#{branch.slug}/edit", else: "/staff/franchise")

    entries = DelivestWeb.StaffNav.settings_entries(assigns.staff, branch)

    active_id = DelivestWeb.StaffNav.active_setting(path)

    entries =
      entries
      |> Enum.reject(
        &(&1.id in [
            :settings,
            :branch_settings,
            :data_transfer,
            :delivery_settings,
            :site_snapshot,
            :instance_backup
          ])
      )
      |> Enum.map(fn entry ->
        %{
          id: "#{assigns.id_prefix}settings-nav-#{entry.id}",
          path:
            DelivestWeb.StaffBranchPath.contextual_navigation_path(
              entry.path,
              assigns.scope_branch,
              assigns.return_source
            ),
          label: entry.label,
          active: entry.id == active_id
        }
      end)

    assigns = assign(assigns, entries: entries)

    ~H"""
    <SubsectionNavigation.subsection_navigation
      id={"#{@id_prefix}settings-navigation"}
      label={gettext("Settings")}
      entries={@entries}
      sidebar={@id_prefix == "sidebar-"}
    />
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
