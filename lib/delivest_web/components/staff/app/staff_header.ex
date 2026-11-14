defmodule DelivestWeb.StaffHeader do
  use DelivestWeb, :html

  attr :current_staff, :map, default: nil
  attr :current_branch, :map, default: nil
  attr :staff_branches, :list, default: []
  attr :current_path, :string, default: nil
  attr :current_uri, :string, default: nil
  attr :settings_branch, :any, default: nil
  attr :page_title, :string, default: nil
  attr :workspace, :boolean, default: false
  attr :page_header, :any, default: nil
  attr :kitchen_status, :any, default: nil
  slot :actions

  def staff_header(assigns) do
    branch = scope_branch(assigns.current_path, assigns.current_branch, assigns.settings_branch)

    assigns = assign(assigns, scope_branch: branch)

    ~H"""
    <header
      id="staff-header"
      class="staff-header fixed inset-x-0 top-0 z-30 flex h-14 items-center gap-3 border-b border-base-300 bg-base-100 px-3 lg:pl-6"
    >
      <div
        id="staff-header-sidebar-controls"
        class="staff-header-sidebar-controls shrink-0 items-center gap-1"
      >
        <button
          id="header-sidebar-toggle"
          type="button"
          data-sidebar-toggle
          phx-click={JS.dispatch("sidebar:toggle")}
          data-expand-label={gettext("Expand menu")}
          data-collapse-label={gettext("Collapse menu")}
          aria-controls="main-sidebar"
          aria-expanded="false"
          aria-label={gettext("Expand menu")}
          title={gettext("Expand menu")}
          class="btn btn-ghost btn-square btn-sm shrink-0"
        >
          <.icon name="panel-left" class="size-5" />
        </button>
      </div>
      <div class="flex w-56 max-w-[55vw] shrink-0 items-center">
        <DelivestWeb.BranchSwitcher.branch_switcher
          current_branch={@scope_branch}
          branches={@staff_branches}
          section={DelivestWeb.StaffBranchPath.section(@current_path)}
          from={@current_uri || @current_path}
          aggregate={@current_path == "/staff/dashboard"}
        />
      </div>
      <div class="ml-auto flex shrink-0 items-center gap-2">
        <DelivestWeb.CommandPalette.command_palette_trigger icon_only />
        <DelivestWeb.KitchenControl.kitchen_indicator
          :if={working_context?(@current_path)}
          status={@kitchen_status}
        />
      </div>
    </header>
    """
  end

  def page_header(%{socket: %{view: view}} = assigns) do
    if function_exported?(view, :staff_page_header, 1), do: view.staff_page_header(assigns)
  end

  def settings_branch(assigns) do
    branches = assigns[:staff_branches] || []

    Enum.find_value(
      [assigns[:settings_scope_branch], assigns[:selected_branch], assigns[:branch]],
      fn candidate ->
        if candidate && Map.get(candidate, :id) && Map.get(candidate, :slug) &&
             Enum.any?(branches, &(&1.id == candidate.id)),
           do: candidate
      end
    )
  end

  def navigation_branch_from_assigns(assigns) do
    branches = assigns[:staff_branches] || []

    accessible = fn candidate ->
      if candidate && Map.get(candidate, :id) && Map.get(candidate, :slug) &&
           Enum.any?(branches, &(&1.id == candidate.id)),
         do: candidate
    end

    scope_branch_from_assigns(assigns) ||
      Enum.find_value(
        [assigns[:navigation_branch], settings_branch(assigns), assigns[:current_branch]],
        accessible
      ) || List.first(branches)
  end

  def scope_branch_from_assigns(assigns) do
    scope_branch(assigns[:current_path], assigns[:current_branch], settings_branch(assigns))
  end

  def scope_branch(path, current_branch, settings_branch) do
    cond do
      shared_integration?(path) -> nil
      String.starts_with?(path || "", "/staff/b/") -> current_branch
      String.starts_with?(path || "", "/staff/branches/") -> settings_branch
      path in ["/staff/settings", "/staff/integrations"] -> settings_branch
      true -> nil
    end
  end

  defp shared_integration?(path) when is_binary(path),
    do:
      String.match?(path, ~r{^/staff(?:/b/[^/]+)?/integrations/(?:dadata|zvonok|yookassa)$}) or
        path == "/staff/integrations/yandex-eda"

  defp shared_integration?(_), do: false

  defp working_context?(path) when is_binary(path),
    do: String.match?(path, ~r{^/staff/b/[^/]+/(?:orders(?:/|$)|kitchen$|pos$)})

  defp working_context?(_), do: false
end
