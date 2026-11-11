defmodule DelivestWeb.StaffHeader do
  use DelivestWeb, :html

  import Delivest.Identity.Acl

  attr :current_staff, :map, default: nil
  attr :current_branch, :map, default: nil
  attr :current_path, :string, default: nil
  attr :settings_branch, :any, default: nil
  attr :page_title, :string, default: nil
  attr :new_orders_count, :integer, default: 0
  attr :kitchen_status, :any, default: nil
  slot :actions

  def staff_header(assigns) do
    assigns =
      assign(assigns,
        context:
          page_context(assigns.current_path, assigns.current_branch, assigns.settings_branch) ||
            gettext("Network")
      )

    ~H"""
    <header
      id="staff-header"
      class="staff-header fixed top-0 right-0 z-30 flex h-16 items-center justify-between gap-3 border-b border-base-300 bg-base-100 px-4 sm:px-6"
    >
      <div class="flex min-w-0 flex-1 items-center gap-2 text-sm" aria-label={gettext("Current page")}>
        <span
          id="staff-header-context"
          class="hidden max-w-36 shrink-0 truncate text-base-content/55 md:block"
          title={@context}
        >
          {@context}
        </span>
        <span aria-hidden="true" class="hidden text-base-content/40 md:block">/</span>
        <div id="staff-header-title" class="min-w-0 flex-1">
          <h1
            class="staff-header-fallback block truncate text-base font-semibold sm:text-lg"
            title={@page_title}
          >
            {@page_title || gettext("Dashboard")}
          </h1>
        </div>
      </div>

      <div class="flex shrink-0 items-center gap-2">
        {render_slot(@actions)}
        <DelivestWeb.GatewayNote.gateway_badge branch={@current_branch} />
        <DelivestWeb.KitchenControl.kitchen_indicator status={@kitchen_status} />
        <DelivestWeb.NewOrdersBell.new_orders_bell
          :if={@current_branch && can?(@current_staff, "orders.read")}
          count={@new_orders_count}
          branch={@current_branch}
        />
      </div>
    </header>
    """
  end

  defp page_context(path, current_branch, settings_branch) when is_binary(path) do
    cond do
      String.starts_with?(path, "/staff/b/") ->
        branch_name(current_branch)

      String.match?(path, ~r{^/staff/branches/[^/]+/edit(?:/|$)}) ->
        branch_name(settings_branch)

      true ->
        nil
    end
  end

  defp page_context(_path, _current_branch, _settings_branch), do: nil

  defp branch_name(%{name: name}) when is_binary(name) and name != "", do: name
  defp branch_name(_branch), do: nil
end
