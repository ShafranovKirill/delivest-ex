defmodule DelivestWeb.StaffHeader do
  use DelivestWeb, :html
  alias DelivestWeb.Staff.ProductLive.ProductTags

  attr :current_staff, :map, default: nil
  attr :current_branch, :map, default: nil
  attr :current_path, :string, default: nil
  attr :settings_branch, :any, default: nil
  attr :page_title, :string, default: nil
  attr :workspace, :boolean, default: false
  attr :page_header, :any, default: nil
  attr :kitchen_status, :any, default: nil
  slot :actions

  def staff_header(assigns) do
    settings_scope =
      settings_scope(assigns.current_path, assigns.current_branch, assigns.settings_branch)

    assigns =
      assign(assigns,
        settings_scope: settings_scope,
        product_section:
          if(assigns.current_branch, do: ProductTags.section(assigns.current_path)),
        context:
          settings_scope || page_context(assigns.current_path, assigns.current_branch) ||
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
        {@page_header}
      </div>
      <div
        :if={is_nil(@product_section)}
        class={[
          "flex min-w-0 flex-1 items-center gap-2 text-sm",
          @settings_scope && "max-md:flex-col max-md:items-start max-md:justify-center max-md:gap-0"
        ]}
        aria-label={gettext("Current page")}
      >
        <span
          id="staff-header-context"
          class={[
            "shrink-0 truncate text-base-content/70 md:max-w-48",
            if(@workspace,
              do: "max-w-full text-sm",
              else: if(@settings_scope, do: "max-w-full text-xs md:text-sm", else: "hidden md:block")
            )
          ]}
          title={@context}
        >
          {@context}
        </span>
        <span :if={not @workspace} aria-hidden="true" class="hidden text-base-content/40 md:block">/</span>
        <div
          :if={not @workspace}
          id="staff-header-title"
          class={[
            "min-w-0 flex-1",
            @settings_scope && "max-md:h-auto! max-md:w-full max-md:flex-none"
          ]}
        >
          <h1
            :if={is_nil(@page_header)}
            class="staff-header-fallback flex h-full min-w-0 items-center truncate text-base font-semibold sm:text-lg"
            title={@page_title}
          >
            {@page_title || gettext("Dashboard")}
          </h1>
          {@page_header}
        </div>
      </div>

      <div class="staff-header-utilities flex shrink-0 items-center gap-2">
        {render_slot(@actions)}
        <DelivestWeb.GatewayNote.gateway_badge branch={@current_branch} />
        <DelivestWeb.KitchenControl.kitchen_indicator status={@kitchen_status} />
      </div>
    </header>
    """
  end

  def page_header(%{socket: %{view: view}} = assigns) do
    if function_exported?(view, :staff_page_header, 1) do
      view.staff_page_header(assigns)
    end
  end

  defp settings_scope(path, current_branch, settings_branch) when is_binary(path) do
    cond do
      path == "/staff/settings" or String.match?(path, ~r{^/staff/franchise(?:/|$)}) or
        String.match?(path, ~r{^/staff(?:/b/[^/]+)?/integrations/(?:dadata|zvonok|yookassa)$}) or
          path == "/staff/integrations/yandex-eda" ->
        gettext("All branches")

      String.match?(path, ~r{^/staff/branches/[^/]+/edit(?:/|$)}) ->
        branch_scope(settings_branch)

      String.match?(
        path,
        ~r{^/staff/b/[^/]+/(?:delivery(?:/|$)|finance/payments$|integrations/[^/]+$)}
      ) ->
        branch_scope(current_branch)

      true ->
        nil
    end
  end

  defp settings_scope(_path, _current_branch, _settings_branch), do: nil

  defp branch_scope(%{name: name}) when is_binary(name) and name != "",
    do: gettext("Branch: %{name}", name: name)

  defp branch_scope(_branch), do: nil

  defp page_context("/staff/b/" <> _path, current_branch), do: branch_name(current_branch)
  defp page_context(_path, _current_branch), do: nil

  defp branch_name(%{name: name}) when is_binary(name) and name != "", do: name
  defp branch_name(_branch), do: nil
end
