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
  attr :id_prefix, :string, default: ""

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
    <ul
      :if={@id_prefix == "sidebar-"}
      id={"#{@id_prefix}settings-navigation"}
      phx-hook="ActiveSectionNav"
      aria-label={gettext("Settings")}
    >
      <li :for={entry <- @entries}>
        <details
          :if={entry.id == :data_system}
          id="sidebar-group-data-system"
          open={@active_id == :data_system}
          phx-mounted={JS.ignore_attributes("open")}
        >
          <summary
            id="sidebar-group-data-system-toggle"
            class={@active_id == :data_system && "menu-active"}
          >
            {entry.label}
          </summary>
          <ul>
            <li :for={child <- DelivestWeb.StaffNav.data_system_entries()}>
              <.link
                id={"#{@id_prefix}logs-tab-#{child.id}"}
                navigate={child.path}
                class={
                  DelivestWeb.StaffNav.active_data_system(@current_path) == child.id && "menu-active"
                }
                aria-current={
                  DelivestWeb.StaffNav.active_data_system(@current_path) == child.id && "page"
                }
              >{child.label}</.link>
            </li>
          </ul>
        </details>
        <.link
          :if={entry.id != :data_system}
          id={"#{@id_prefix}settings-nav-#{entry.id}"}
          navigate={
            DelivestWeb.StaffBranchPath.contextual_navigation_path(
              entry.path,
              @scope_branch,
              @return_source
            )
          }
          class={entry.id == @active_id && "menu-active"}
          aria-current={entry.id == @active_id && "page"}
        >{entry.label}</.link>
      </li>
    </ul>
    <nav
      :if={@id_prefix == ""}
      id={"#{@id_prefix}settings-navigation"}
      phx-hook="ActiveSectionNav"
      class={[
        "flex gap-2 rounded-box border border-base-300 bg-base-100 p-2",
        @variant == :sidebar &&
          "min-w-0 max-w-full self-start overflow-x-auto w-full",
        @variant == :horizontal && "flex-wrap items-center"
      ]}
      aria-label={gettext("Settings")}
    >
      <.link
        :for={entry <- @entries}
        id={"#{@id_prefix}settings-nav-#{entry.id}"}
        navigate={
          DelivestWeb.StaffBranchPath.contextual_navigation_path(
            entry.path,
            @scope_branch,
            @return_source
          )
        }
        class={[
          "btn btn-sm btn-ghost shrink-0",
          @variant == :sidebar && "2xl:justify-start",
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
