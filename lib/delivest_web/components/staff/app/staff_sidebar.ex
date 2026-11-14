defmodule DelivestWeb.StaffSidebar do
  use DelivestWeb, :html

  import Delivest.Identity.Acl

  attr :current_page, :atom, default: nil
  attr :current_staff, :map, default: nil
  attr :current_branch, :map, default: nil
  attr :scope_branch, :map, default: nil
  attr :navigation_branch, :map, default: nil
  attr :staff_branches, :list, default: []
  attr :current_path, :string, default: nil
  attr :current_uri, :string, default: nil
  attr :new_orders_count, :integer, default: 0
  attr :page_navigation, :any, default: nil

  def staff_sidebar(assigns) do
    navigation_branch = assigns.navigation_branch || assigns.current_branch
    navigation_branch = navigation_branch && Delivest.Repo.preload(navigation_branch, :info)

    entries =
      DelivestWeb.StaffNav.entries(
        assigns.current_staff,
        navigation_branch,
        assigns.current_branch
      )

    entries =
      if assigns.scope_branch do
        entries
      else
        Enum.map(entries, fn
          %{id: :main, entries: items} = section ->
            %{
              section
              | entries:
                  Enum.map(items, fn
                    %{id: :dashboard} = item -> %{item | path: ~p"/staff/dashboard"}
                    item -> item
                  end)
            }

          section ->
            section
        end)
      end

    return_source = assigns.current_uri || assigns.current_path

    entries =
      Enum.map(entries, fn section ->
        %{
          section
          | entries:
              Enum.map(
                section.entries,
                &contextual_entry(&1, assigns.scope_branch, return_source)
              )
        }
      end)

    assigns = assign(assigns, entries: entries)

    ~H"""
    <aside
      id="main-sidebar"
      class="staff-sidebar fixed inset-y-0 left-0 z-50 flex flex-col border-r border-base-300 bg-base-100 transition-[width] duration-300"
    >
      <div class="shrink-0 space-y-3 p-2">
        <div
          id="sidebar-top-row"
          class="staff-sidebar-top-row flex items-center justify-between gap-1"
        >
          <.link
            id="sidebar-home"
            href={~p"/staff"}
            class="staff-sidebar-top-link flex shrink-0 items-center rounded-field p-1 hover:bg-base-200"
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
          <div class="staff-sidebar-top-actions flex items-center gap-1">
            <DelivestWeb.NewOrdersBell.new_orders_bell
              :if={@scope_branch && can?(@current_staff, "orders.read")}
              count={@new_orders_count}
              branch={@scope_branch}
            />
            <button
              id="sidebar-toggle"
              type="button"
              data-sidebar-toggle
              phx-click={JS.dispatch("sidebar:toggle")}
              data-expand-label={gettext("Expand menu")}
              data-collapse-label={gettext("Collapse menu")}
              aria-controls="main-sidebar"
              aria-expanded="false"
              aria-label={gettext("Expand menu")}
              title={gettext("Expand menu")}
              class="staff-sidebar-toggle btn btn-ghost btn-square btn-sm shrink-0"
            >
              <.icon name="panel-left" class="size-5" />
            </button>
          </div>
        </div>
      </div>

      <nav class="min-h-0 flex-1 overflow-y-auto overflow-x-hidden overscroll-contain px-2 py-3 [scrollbar-width:thin]">
        <div
          :for={section <- Enum.filter(@entries, &(&1.id == :main))}
          id={"nav-section-#{section.id}"}
          class="flex flex-col gap-1 pb-3"
        >
          <p
            :if={section.label && section.id != :branch}
            class="staff-sidebar-label truncate px-3 pt-1 pb-1 text-xs font-semibold uppercase tracking-wider text-base-content/50"
            title={section.label}
          >
            {section.label}
          </p>
          <div
            :if={section.id != :branch}
            class="hidden h-px bg-base-300 mx-2 mb-1 lg:sidebar-collapsed:block"
          >
          </div>
          <%= for entry <- section.entries do %>
            <ul :if={entry.kind == :item} class="menu w-full p-0">
              <li>
                <%= if @page_navigation && @current_page in entry.pages do %>
                  <.sidebar_accordion id={"sidebar-group-#{entry.id}"} item={entry} open>
                    {@page_navigation}
                  </.sidebar_accordion>
                <% else %>
                  <.nav_link item={entry} current_page={@current_page} />
                <% end %>
              </li>
            </ul>
            <ul :if={entry.kind == :group} class="menu w-full p-0">
              <li>
                <.sidebar_accordion
                  id={"sidebar-group-#{entry.id}"}
                  item={primary_item(entry)}
                  open={group_active?(entry, @current_page, @current_path)}
                >
                  <DelivestWeb.StaffNav.local_navigation
                    id_prefix="sidebar-"
                    group_id={
                      if(group_active?(entry, @current_page, @current_path), do: nil, else: entry.id)
                    }
                    items_override={group_items(entry, @current_staff, @navigation_branch)}
                    staff={@current_staff}
                    branch={@current_branch}
                    navigation_branch={@navigation_branch}
                    current_page={@current_page}
                    current_path={@current_path}
                    scope_branch={@scope_branch}
                    return_source={@current_uri || @current_path}
                  />
                  <%= if @page_navigation && group_active?(entry, @current_page, @current_path) do %>
                    {@page_navigation}
                  <% end %>
                </.sidebar_accordion>
              </li>
            </ul>
          <% end %>
        </div>
        <div
          :for={section <- Enum.filter(@entries, &(&1.id == :settings))}
          id="nav-section-settings"
          class="flex flex-col gap-1 pb-3"
        >
          <.sidebar_accordion
            :for={entry <- section.entries}
            id="sidebar-group-settings"
            item={entry}
            open={not is_nil(DelivestWeb.StaffNav.active_setting(@current_path))}
          >
            <DelivestWeb.Staff.SettingsComponents.settings_navigation
              variant={:sidebar}
              id_prefix="sidebar-"
              staff={@current_staff}
              branches={@staff_branches}
              selected={@navigation_branch && @navigation_branch.id}
              current_path={@current_path}
              scope_branch={@scope_branch}
              return_source={@current_uri || @current_path}
            />
            <%= if @page_navigation && DelivestWeb.StaffNav.active_setting(@current_path) do %>
              {@page_navigation}
            <% end %>
          </.sidebar_accordion>
        </div>
      </nav>

      <div class="staff-sidebar-footer shrink-0 border-t border-base-300 p-1">
        <div class="flex min-w-0 items-center gap-1">
          <DelivestWeb.StaffProfileMenu.staff_profile_menu current_staff={@current_staff} />
        </div>
      </div>
    </aside>

    <div
      id="staff-sidebar-overlay"
      class="staff-sidebar-overlay fixed inset-0 z-40 bg-black/30"
      phx-click={JS.dispatch("sidebar:toggle-open")}
      aria-hidden="true"
    >
    </div>
    """
  end

  defp contextual_entry(%{kind: :group, items: items} = group, scope_branch, return_source) do
    %{group | items: Enum.map(items, &contextual_entry(&1, scope_branch, return_source))}
  end

  defp contextual_entry(%{path: path} = item, scope_branch, return_source) do
    %{
      item
      | path:
          DelivestWeb.StaffBranchPath.contextual_navigation_path(
            path,
            scope_branch,
            return_source
          )
    }
  end

  defp primary_item(group) do
    first = hd(group.items)
    %{first | label: group.label, icon: group.icon, pages: Enum.flat_map(group.items, & &1.pages)}
  end

  defp group_items(%{id: :menu}, staff, branch),
    do: DelivestWeb.StaffNav.menu_items(staff, branch)

  defp group_items(group, _staff, _branch), do: group.items

  defp group_active?(%{id: :menu}, page, path),
    do:
      page == :categories or
        not is_nil(DelivestWeb.Staff.ProductLive.ProductTags.section(path)) or
        (is_binary(path) and String.contains?(path, "/products/operations"))

  defp group_active?(%{id: :marketing}, :marketing, _path), do: true

  defp group_active?(group, page, _path),
    do: Enum.any?(group.items, &(page in &1.pages))

  attr :id, :string, required: true
  attr :item, :map, required: true
  attr :open, :boolean, default: false
  slot :inner_block, required: true

  defp sidebar_accordion(assigns) do
    ~H"""
    <div class="sidebar-accordion relative min-w-0">
      <.nav_link item={@item} current_page={nil} />
      <details
        id={@id}
        open={@open}
        phx-mounted={JS.ignore_attributes("open")}
        class="sidebar-accordion-details"
      >
        <summary
          id={"#{@id}-toggle"}
          class="sidebar-accordion-toggle flex cursor-pointer items-center justify-center rounded-field hover:bg-base-200"
          aria-label={gettext("Toggle %{section} sections", section: @item.label)}
          title={gettext("Toggle %{section} sections", section: @item.label)}
        >
          <.icon name="hero-chevron-down" class="size-4" />
        </summary>
        <div class="sidebar-accordion-content min-w-0 border-l border-base-300 ml-4 pl-1">
          {render_slot(@inner_block)}
        </div>
      </details>
    </div>
    """
  end

  attr :item, :map, required: true
  attr :current_page, :atom, default: nil

  defp nav_link(assigns) do
    ~H"""
    <.link
      navigate={@item.path}
      title={@item.label}
      class={[
        "staff-sidebar-nav-link flex w-full min-w-0 items-center gap-2 overflow-hidden rounded-field px-2.5 py-2 text-[13px] font-medium text-base-content/70 hover:bg-base-200/70 hover:text-base-content",
        @current_page in @item.pages && "menu-active"
      ]}
    >
      <.icon name={@item.icon} class="size-5 shrink-0" />
      <span class="staff-sidebar-label min-w-0 flex-1 truncate">{@item.label}</span>
    </.link>
    """
  end
end
