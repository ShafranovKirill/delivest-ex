defmodule DelivestWeb.StaffSidebar do
  use DelivestWeb, :html

  attr :drawer_id, :string, default: "staff-drawer", doc: "ID чекбокса для DaisyUI drawer"
  attr :current_page, :atom, default: nil, doc: "Текущая активная страница для подсветки пунктов"

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

        <ul class="menu menu-md gap-1">
          <li>
            <.link
              href={~p"/staff/dashboard"}
              class={["rounded-xl hover:bg-base-200", @current_page == :dashboard && "active"]}
            >
              <.icon name="hero-home" class="h-5 w-5" />
              <span>{gettext("Dashboard")}</span>
            </.link>
          </li>
          <li>
            <.link
              href={~p"/staff/auth/log_out"}
              method="delete"
              class="rounded-xl text-error hover:bg-error/10"
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
