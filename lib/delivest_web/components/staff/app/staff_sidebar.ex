defmodule DelivestWeb.StaffSidebar do
  use DelivestWeb, :html

  alias Delivest.Identity

  attr :current_page, :atom, default: nil
  attr :current_staff, :map, default: nil
  attr :current_branch, :map, default: nil
  attr :staff_branches, :list, default: []
  attr :current_path, :string, default: nil

  def staff_sidebar(assigns) do
    assigns =
      assign(assigns,
        entries: DelivestWeb.StaffNav.entries(assigns.current_staff, assigns.current_branch)
      )

    ~H"""
    <aside
      id="main-sidebar"
      class="staff-sidebar fixed inset-y-0 left-0 z-50 flex flex-col border-r border-base-300 bg-base-100 transition-[width] duration-300"
    >
      <div class="shrink-0 space-y-3 border-b border-base-300 p-2">
        <div class="flex items-center justify-between gap-1">
          <.link
            navigate={DelivestWeb.StaffBranchPath.home(@current_branch)}
            class="flex min-w-0 flex-1 items-center gap-2 rounded-field p-1 hover:bg-base-200"
            title="Delivest"
            aria-label="Delivest"
          >
            <img
              src={~p"/images/logo-dark.png"}
              alt=""
              class="size-8 shrink-0 object-contain dark:hidden"
            />
            <img
              src={~p"/images/logo-white.png"}
              alt=""
              class="hidden size-8 shrink-0 object-contain dark:block"
            />
            <span class="staff-sidebar-label truncate text-sm font-bold">Delivest</span>
          </.link>
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
            <.icon name="hero-chevron-double-right" class="staff-sidebar-toggle-icon size-5" />
          </button>
        </div>

        <DelivestWeb.BranchSwitcher.branch_switcher
          current_branch={@current_branch}
          branches={@staff_branches}
          section={DelivestWeb.StaffBranchPath.section(@current_path)}
        />
        <.link
          :if={
            @current_branch &&
              ((Identity.can?(@current_staff, "branches.read") &&
                  Identity.can?(@current_staff, "branches.update")) ||
                 Identity.authorize(@current_staff, "delivery.read", @current_branch.id) == :ok)
          }
          id="sidebar-branch-settings"
          navigate={~p"/staff/branches/#{@current_branch.slug}/edit"}
          title={gettext("Branch settings")}
          class="staff-sidebar-top-link flex items-center gap-2 rounded-field px-2 py-2 text-sm hover:bg-base-200"
        >
          <.icon name="hero-cog-6-tooth" class="size-5 shrink-0" />
          <span class="staff-sidebar-label truncate">{gettext("Branch settings")}</span>
        </.link>
      </div>

      <nav class="min-h-0 flex-1 overflow-y-auto overflow-x-hidden overscroll-contain px-2 py-3 [scrollbar-width:thin]">
        <div
          :for={section <- @entries}
          id={"nav-section-#{section.id}"}
          class="flex flex-col gap-1 pb-3"
        >
          <p
            :if={section.label}
            class="staff-sidebar-label truncate px-3 pt-1 pb-1 text-xs font-semibold uppercase tracking-wider text-base-content/50"
            title={section.label}
          >
            {section.label}
          </p>
          <div class="hidden h-px bg-base-300 mx-2 mb-1 lg:sidebar-collapsed:block"></div>
          <%= for entry <- section.entries do %>
            <ul :if={entry.kind == :item} class="menu w-full p-0">
              <li><.nav_link item={entry} current_page={@current_page} /></li>
            </ul>
            <.nav_group :if={entry.kind == :group} group={entry} current_page={@current_page} />
          <% end %>
        </div>
      </nav>

      <div class="staff-sidebar-footer shrink-0 border-t border-base-300 p-1">
        <div class="flex min-w-0 items-center gap-1">
          <DelivestWeb.StaffProfileMenu.staff_profile_menu current_staff={@current_staff} />
          <DelivestWeb.CommandPalette.command_palette_trigger icon_only />
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

  attr :group, :map, required: true
  attr :current_page, :atom, default: nil

  defp nav_group(assigns) do
    assigns =
      assign(assigns, active: Enum.any?(assigns.group.items, &(assigns.current_page in &1.pages)))

    ~H"""
    <div
      id={"nav-group-#{@group.id}"}
      phx-hook=".SidebarGroup"
      data-open={@active}
      data-active={@active}
      class="group/nav flex flex-col gap-1"
    >
      <div class="hidden h-px bg-base-300 mx-2 my-1 lg:sidebar-collapsed:block"></div>
      <button
        type="button"
        data-toggle
        title={@group.label}
        class={[
          "staff-sidebar-group-toggle flex w-full cursor-pointer items-center gap-2 rounded-field px-2.5 py-2 text-[13px] font-medium text-base-content/70 hover:bg-base-200/70 hover:text-base-content",
          @active && "bg-base-200/70 text-base-content"
        ]}
      >
        <.icon name={@group.icon} class="size-5 shrink-0" />
        <span class="staff-sidebar-label truncate">{@group.label}</span>
        <.icon
          name="hero-chevron-right"
          class="ml-auto size-3.5 shrink-0 transition-transform group-data-open/nav:rotate-90"
        />
      </button>
      <ul class="staff-sidebar-group-list menu w-full gap-1 hidden border-l border-base-300 ml-6 p-0 pl-2 group-data-open/nav:flex">
        <li :for={item <- @group.items}>
          <.nav_link item={item} current_page={@current_page} />
        </li>
      </ul>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".SidebarGroup">
      const key = "sidebar_groups"
      const read = () => {
        try { return JSON.parse(localStorage.getItem(key) || "{}") } catch { return {} }
      }

      export default {
        mounted() {
          this.apply()
          this.el.querySelector("[data-toggle]").addEventListener("click", () => {
            const open = this.el.toggleAttribute("data-open")
            localStorage.setItem(key, JSON.stringify({ ...read(), [this.el.id]: open }))
          })
        },
        updated() {
          this.apply()
        },
        apply() {
          const saved = read()[this.el.id]
          if (!this.el.hasAttribute("data-active") && saved !== undefined)
            this.el.toggleAttribute("data-open", saved)
        }
      }
    </script>
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
        "staff-sidebar-nav-link flex items-center gap-2 rounded-field px-2.5 py-2 text-[13px] font-medium text-base-content/70 hover:bg-base-200/70 hover:text-base-content",
        @current_page in @item.pages && "menu-active"
      ]}
    >
      <.icon name={@item.icon} class="size-5 shrink-0" />
      <span class="staff-sidebar-label truncate">{@item.label}</span>
    </.link>
    """
  end
end
