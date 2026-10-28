defmodule DelivestWeb.StaffSidebar do
  use DelivestWeb, :html

  attr :current_page, :atom, default: nil
  attr :current_staff, :map, default: nil
  attr :current_branch, :map, default: nil

  def staff_sidebar(assigns) do
    assigns =
      assign(assigns,
        entries: DelivestWeb.StaffNav.entries(assigns.current_staff, assigns.current_branch)
      )

    ~H"""
    <aside
      id="main-sidebar"
      class={[
        "group/sidebar fixed left-0 top-16 bottom-0 z-40 flex w-72 flex-col",
        "border-r border-base-300 bg-base-100 transition-[width,translate] duration-300",
        "-translate-x-full sidebar-open:translate-x-0 lg:translate-x-0 lg:sidebar-collapsed:w-20"
      ]}
    >
      <nav class="flex-1 min-h-0 overflow-y-auto overflow-x-hidden overscroll-contain px-3 py-3 [scrollbar-width:thin]">
        <div
          :for={section <- @entries}
          id={"nav-section-#{section.id}"}
          class="flex flex-col gap-1 pb-3"
        >
          <p
            :if={section.label}
            class="truncate px-3 pt-1 pb-1 text-xs font-semibold uppercase tracking-wider text-base-content/50 lg:sidebar-collapsed:hidden"
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

      <button
        type="button"
        phx-click={JS.dispatch("sidebar:toggle-collapse")}
        class="hidden lg:flex shrink-0 items-center gap-2 border-t border-base-300 px-6 py-3 text-sm text-base-content/60 hover:text-base-content hover:bg-base-200 transition-colors cursor-pointer lg:sidebar-collapsed:justify-center lg:sidebar-collapsed:px-0"
        title={gettext("Collapse menu")}
      >
        <.icon
          name="hero-chevron-double-left"
          class="size-5 shrink-0 transition-transform duration-300 lg:sidebar-collapsed:rotate-180"
        />
        <span class="lg:sidebar-collapsed:hidden">{gettext("Collapse menu")}</span>
        <span
          id="app-version"
          class="ml-auto font-mono text-xs text-base-content/40 lg:sidebar-collapsed:hidden"
        >
          v{Application.get_env(:delivest, :version, "dev")}
        </span>
      </button>
    </aside>

    <div
      class="fixed inset-0 top-16 z-30 hidden bg-black/30 sidebar-open:block lg:sidebar-open:hidden"
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
          "flex w-full items-center gap-2 rounded-field px-3 py-2 cursor-pointer hover:bg-base-200",
          "lg:sidebar-collapsed:hidden",
          @active && "text-primary"
        ]}
      >
        <.icon name={@group.icon} class="size-6 shrink-0" />
        <span class="font-bold truncate">{@group.label}</span>
        <.icon
          name="hero-chevron-right"
          class="ml-auto size-4 shrink-0 transition-transform group-data-open/nav:rotate-90"
        />
      </button>
      <ul class={[
        "menu w-full p-0 gap-1 hidden border-l border-base-300 ml-6 pl-2 group-data-open/nav:flex",
        "lg:sidebar-collapsed:flex lg:sidebar-collapsed:ml-0 lg:sidebar-collapsed:pl-0 lg:sidebar-collapsed:border-l-0"
      ]}>
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
        "flex items-center gap-2 px-3 py-2",
        "lg:sidebar-collapsed:justify-center lg:sidebar-collapsed:px-2",
        @current_page in @item.pages && "menu-active"
      ]}
    >
      <.icon name={@item.icon} class="size-6 shrink-0" />
      <span class="font-bold truncate lg:sidebar-collapsed:hidden">{@item.label}</span>
    </.link>
    """
  end
end
