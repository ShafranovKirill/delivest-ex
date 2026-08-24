defmodule DelivestWeb.StaffSidebar do
  alias Delivest.Identity
  use DelivestWeb, :html
  import Identity.Acl

  attr :current_page, :atom, default: nil
  attr :current_staff, :map, default: nil
  attr :drawer_id, :string, default: "staff-drawer", doc: "ID чекбокса для DaisyUI drawer"

  def staff_sidebar(assigns) do
    ~H"""
    <aside
      id="main-sidebar"
      phx-hook="Sidebar"
      class={[
        "peer group/sidebar fixed inset-y-0 left-0 z-50 flex flex-col h-full border-r border-base-300 bg-base-100 transition-all duration-300 ease-in-out mt-16 lg:mt-0 pb-16 lg:pb-0 lg:static",
        "w-72 [&.is-collapsed]:w-20",
        "-translate-x-full lg:translate-x-0 [&.is-mobile-open]:translate-x-0"
      ]}
    >
      <button
        phx-click={JS.toggle_class("is-collapsed", to: "#main-sidebar")}
        class="absolute -right-3 top-10 z-60 hidden  lg:flex btn btn-square btn-xs btn-primary border border-base-300 items-center justify-center"
      >
        <.icon
          name="hero-chevron-left"
          class="size-3 transition-transform duration-300 group-[.is-collapsed]/sidebar:rotate-180"
        />
      </button>

      <div class="h-20 flex flex-col justify-center px-6 shrink-0">
        <p class="text-xs uppercase tracking-[0.2em] text-base-content/50 group-[.is-collapsed]/sidebar:hidden">
          {gettext("Workspace")}
        </p>
        <h2 class="mt-1 text-lg font-bold text-base-content group-[.is-collapsed]/sidebar:hidden truncate">
          {gettext("Delivest")}
        </h2>

        <div class="hidden group-[.is-collapsed]/sidebar:flex items-center justify-start">
          <img
            src={~p"/images/logo-dark.png"}
            alt={gettext("Delivest")}
            class="size-8 object-contain dark:hidden"
          />

          <img
            src={~p"/images/logo-white.png"}
            alt={gettext("Delivest")}
            class="size-8 object-contain hidden dark:block"
          />
        </div>
      </div>

      <nav class="flex-1 overflow-y-auto overflow-x-hidden px-3 mt-2 space-y-1">
        <ul class="menu w-full p-0 gap-1">
          <li>
            <.link
              navigate={~p"/staff/dashboard"}
              class={[
                "flex items-center gap-2",
                (@current_page == :dashboard && "menu-active") || ""
              ]}
            >
              <.icon name="hero-squares-2x2" class="size-6 shrink-0" />
              <span class="group-[.is-collapsed]/sidebar:hidden font-bold truncate">
                {gettext("Dashboard")}
              </span>
            </.link>
          </li>
        </ul>

        <%= if can_any?(@current_staff, ["categories.read", "products.read"]) do %>
          <div class="py-4 overflow-hidden">
            <div class="h-px bg-base-300 w-full"></div>
            <div class="mt-4 px-3 text-[10px] font-black text-base-content/50 uppercase tracking-widest group-[.is-collapsed]/sidebar:hidden">
              {gettext("Catalog")}
            </div>
          </div>

          <ul class="menu w-full p-0 gap-1">
            <li :if={can?(@current_staff, "categories.read")}>
              <.link
                navigate={~p"/staff/categories"}
                class={[
                  "flex items-center gap-2",
                  (@current_page == :categories && "menu-active") || ""
                ]}
              >
                <.icon name="hero-rectangle-stack" class="size-6 shrink-0" />
                <span class="group-[.is-collapsed]/sidebar:hidden font-bold truncate">
                  {gettext("Categories")}
                </span>
              </.link>
            </li>

            <li :if={can?(@current_staff, "products.read")}>
              <.link
                navigate={~p"/staff/products"}
                class={[
                  "flex items-center gap-2",
                  (@current_page == :products && "menu-active") || ""
                ]}
              >
                <.icon name="hero-cube" class="size-6 shrink-0" />
                <span class="group-[.is-collapsed]/sidebar:hidden font-bold truncate">
                  {gettext("Products")}
                </span>
              </.link>
            </li>
          </ul>
        <% end %>

        <%= if can_any?(@current_staff, ["branches.read", "staff.read", "roles.read"]) do %>
          <div class="py-4 overflow-hidden">
            <div class="h-px bg-base-300 w-full"></div>
            <div class="mt-4 px-3 text-[10px] font-black text-base-content/50 uppercase tracking-widest group-[.is-collapsed]/sidebar:hidden">
              {gettext("Company")}
            </div>
          </div>

          <ul class="menu w-full p-0 gap-1">
            <li :if={can?(@current_staff, "branches.read")}>
              <.link
                navigate={~p"/staff/branches"}
                class={[
                  "flex items-center gap-2",
                  (@current_page == :branches && "menu-active") || ""
                ]}
              >
                <.icon name="hero-map-pin" class="size-6 shrink-0" />
                <span class="group-[.is-collapsed]/sidebar:hidden font-bold truncate">
                  {gettext("Branches")}
                </span>
              </.link>
            </li>

            <li :if={can?(@current_staff, "staff.read")}>
              <.link
                navigate={~p"/staff/employee"}
                class={[
                  "flex items-center gap-2",
                  (@current_page == :employee && "menu-active") || ""
                ]}
              >
                <.icon name="hero-users" class="size-6 shrink-0" />
                <span class="group-[.is-collapsed]/sidebar:hidden font-bold truncate">
                  {gettext("Staff")}
                </span>
              </.link>
            </li>

            <li :if={can?(@current_staff, "roles.read")}>
              <.link
                navigate={~p"/staff/roles"}
                class={[
                  "flex items-center gap-2",
                  (@current_page == :roles && "menu-active") || ""
                ]}
              >
                <.icon name="hero-shield-check" class="size-6 shrink-0" />
                <span class="group-[.is-collapsed]/sidebar:hidden font-bold truncate">
                  {gettext("Roles")}
                </span>
              </.link>
            </li>
          </ul>
        <% end %>
      </nav>

      <div class="p-3 border-t border-base-300 shrink-0 flex flex-col gap-1">
        <ul class="menu p-0 w-full gap-1">
          <li>
            <.link
              patch={~p"/staff/branches/select"}
              class="flex items-center gap-2 text-primary hover:bg-primary/10"
            >
              <.icon name="hero-arrow-path-rounded-square" class="size-6 shrink-0" />
              <span class="group-[.is-collapsed]/sidebar:hidden font-bold truncate">
                {gettext("Change branch")}
              </span>
            </.link>
          </li>

          <li>
            <.link
              href={~p"/staff/auth/log_out"}
              method="delete"
              class="flex items-center gap-2 text-error hover:bg-error/10 hover:text-error"
            >
              <.icon name="hero-arrow-right-start-on-rectangle" class="size-6 shrink-0" />
              <span class="group-[.is-collapsed]/sidebar:hidden font-bold truncate">
                {gettext("Log out")}
              </span>
            </.link>
          </li>
        </ul>
      </div>
    </aside>
    """
  end
end
