defmodule DelivestWeb.StaffSidebar do
  alias Delivest.Identity
  use DelivestWeb, :html
  import Identity.Acl

  attr :current_page, :atom, default: nil
  attr :current_staff, :map, default: nil
  attr :drawer_id, :string, default: "staff-drawer", doc: "ID чекбокса для DaisyUI drawer"

  def staff_sidebar(assigns) do
    ~H"""
    <aside class="drawer-side z-40">
      <label for={@drawer_id} aria-label={gettext("Close menu")} class="drawer-overlay"></label>

      <div class="menu min-h-full w-72 bg-base-100 p-4 pt-20 text-base-content border-r border-base-300">
        <div class="px-2 py-3 mb-4">
          <p class="text-xs uppercase tracking-[0.2em] text-base-content/50">
            {gettext("Workspace")}
          </p>
          <h2 class="mt-1 text-lg font-bold text-base-content">{gettext("Delivest")}</h2>
        </div>

        <ul class="menu w-full p-0 gap-1">
          <li>
            <.link
              navigate={~p"/staff/dashboard"}
              class={(@current_page == :dashboard && "menu-active") || ""}
            >
              {gettext("Dashboard")}
            </.link>
          </li>

          <li :if={can_any?(@current_staff, ["branches.read", "staff.read", "roles.read"])}>
            <details open={@current_page in [:orders_active, :orders_archive]}>
              <summary class="font-medium">
                {gettext("Company")}
              </summary>
              <ul>
                <li :if={can?(@current_staff, "branches.read")}>
                  <.link
                    navigate={~p"/staff/orders/active"}
                    class={(@current_page == :orders_active && "menu-active") || ""}
                  >
                    {gettext("Branches")}
                  </.link>
                </li>
                <li :if={can_any?(@current_staff, ["staff.read", "roles.read"])}>
                  <details open={@current_page in [:orders_active, :orders_archive]}>
                    <summary class="font-medium">
                      {gettext("Staff")}
                    </summary>

                    <li :if={can?(@current_staff, "staff.read")}>
                      <.link
                        navigate={~p"/staff/orders/active"}
                        class={(@current_page == :orders_active && "menu-active") || ""}
                      >
                        {gettext("Employee")}
                      </.link>
                    </li>
                    <li :if={can?(@current_staff, "roles.read")}>
                      <.link
                        navigate={~p"/staff/orders/active"}
                        class={(@current_page == :orders_active && "menu-active") || ""}
                      >
                        {gettext("Roles")}
                      </.link>
                    </li>
                  </details>
                </li>
              </ul>
            </details>
          </li>

          <li>
            <.link
              href={~p"/staff/auth/log_out"}
              method="delete"
              class="text-error hover:bg-error/10"
            >
              <.icon name="hero-arrow-right-start-on-rectangle" class="h-5 w-5" />
              <span>{gettext("Log out")}</span>
            </.link>
          </li>
        </ul>
      </div>
    </aside>
    """
  end
end
