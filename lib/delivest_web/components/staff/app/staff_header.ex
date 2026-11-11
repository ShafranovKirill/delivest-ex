defmodule DelivestWeb.StaffHeader do
  use DelivestWeb, :html
  alias DelivestWeb.Staff.ProductLive.ProductTags

  attr :current_staff, :map, default: nil
  attr :current_branch, :map, default: nil
  attr :current_path, :string, default: nil
  attr :settings_branch, :any, default: nil
  attr :page_title, :string, default: nil
  attr :kitchen_status, :any, default: nil
  slot :actions

  def staff_header(assigns) do
    assigns =
      assign(assigns,
        product_section:
          if(assigns.current_branch, do: ProductTags.section(assigns.current_path)),
        context:
          page_context(assigns.current_path, assigns.current_branch, assigns.settings_branch) ||
            gettext("Network")
      )

    ~H"""
    <header
      id="staff-header"
      data-header-layout={if @product_section, do: "product-tabs"}
      data-header-actions={
        if @product_section, do: to_string(ProductTags.actions?(@product_section, @current_staff))
      }
      class="staff-header fixed top-0 right-0 z-30 flex h-16 items-center justify-between gap-3 border-b border-base-300 bg-base-100 pl-3 pr-0 sm:px-6"
    >
      <div
        id="staff-header-sidebar-controls"
        class="staff-header-sidebar-controls shrink-0 items-center gap-1"
      >
        <.link
          id="header-home"
          navigate={DelivestWeb.StaffBranchPath.home(@current_branch)}
          class="flex shrink-0 items-center rounded-field p-1 hover:bg-base-200"
          title="Delivest"
          aria-label="Delivest"
        >
          <img
            src={~p"/images/logo-dark.png"}
            alt=""
            class="size-6 shrink-0 object-contain dark:hidden"
          />
          <img
            src={~p"/images/logo-white.png"}
            alt=""
            class="hidden size-6 shrink-0 object-contain dark:block"
          />
        </.link>
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
          <.icon name="panel-left" class="size-6" />
        </button>
      </div>
      <div :if={@product_section} class="flex min-w-0 flex-1 items-center text-sm">
        <.header_navigation label={gettext("Products")}>
          <ProductTags.tabs
            current={if(@product_section == :bulk, do: :products, else: @product_section)}
            branch={@current_branch}
          />
        </.header_navigation>
      </div>
      <div
        :if={is_nil(@product_section)}
        class="flex min-w-0 flex-1 items-center gap-2 text-sm"
        aria-label={gettext("Current page")}
      >
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

      <div
        id="staff-header-actions"
        phx-hook="HeaderScroll"
        class="staff-header-actions staff-header-scroll"
      >
        <div
          id="staff-header-actions-scroll"
          class="staff-header-actions-scroll"
          data-scroll-viewport
        />
      </div>

      <div class="staff-header-utilities flex shrink-0 items-center gap-2">
        {render_slot(@actions)}
        <DelivestWeb.GatewayNote.gateway_badge branch={@current_branch} />
        <DelivestWeb.KitchenControl.kitchen_indicator status={@kitchen_status} />
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
