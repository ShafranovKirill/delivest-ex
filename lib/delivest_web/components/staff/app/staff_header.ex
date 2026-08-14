defmodule DelivestWeb.StaffHeader do
  use DelivestWeb, :html

  attr :current_staff, :map, default: nil
  attr :drawer_id, :string, default: "staff-drawer"

  def staff_header(assigns) do
    ~H"""
    <header class="fixed top-0 left-0 right-0 z-50 bg-base-100 border-b border-base-300 px-4 sm:px-6 h-16 flex items-center justify-between shrink-0">
      <div class="flex items-center gap-3">
        <label
          for={@drawer_id}
          class="btn btn-ghost btn-square rounded-xl w-10 h-10 btn-sm border border-base-300 bg-base-100 shadow-sm hover:bg-base-200"
          aria-label={gettext("Open menu")}
        >
          <.icon name="hero-bars-3" class="h-5 w-5" />
        </label>

        <a
          href="/staff/dashboard"
          class="font-bold text-xl tracking-tight text-base-content hover:text-primary transition-colors"
        >
          {gettext("Delivest CRM")}
        </a>
      </div>

      <div class="flex items-center gap-4">
        <%= if @current_staff do %>
          <% current_locale = Gettext.get_locale(DelivestWeb.Gettext) %>
          <% staff_name =
            if @current_staff.name && @current_staff.name != "",
              do: @current_staff.name,
              else: gettext("Staff")

          initial = String.first(staff_name) |> String.upcase() %>

          <div class="dropdown dropdown-end">
            <div
              tabindex="0"
              role="button"
              class="flex items-center gap-3 cursor-pointer py-1 px-2 rounded-xl hover:bg-base-200 transition-colors"
            >
              <div class="avatar placeholder">
                <div class="bg-primary text-primary-content rounded-xl w-10 h-10 flex items-center justify-center font-bold text-sm">
                  <span>{initial}</span>
                </div>
              </div>

              <div class="flex flex-col text-left">
                <span class="text-sm font-semibold text-base-content leading-tight">
                  {staff_name}
                </span>
                <span class="text-xs text-base-content/60 leading-tight mt-0.5">
                  {@current_staff.role.name}
                </span>
              </div>
            </div>

            <ul
              tabindex="0"
              class="dropdown-content z-1 menu p-2 shadow-lg bg-base-100 rounded-box w-52 border border-base-300 mt-2"
            >
              <li class="menu-title px-4 py-2 text-xs font-semibold text-base-content/50 uppercase tracking-wider">
                {gettext("Language")}
              </li>
              <li>
                <%= if current_locale == "ru" do %>
                  <.link href={~p"/locale/en"} class="flex items-center justify-between">
                    <span>🇬🇧 English</span>
                  </.link>
                <% else %>
                  <.link href={~p"/locale/ru"} class="flex items-center justify-between">
                    <span>🇷🇺 Русский</span>
                  </.link>
                <% end %>
              </li>

              <div class="divider my-1"></div>

              <li class="menu-title px-4 py-2 text-xs font-semibold text-base-content/50 uppercase tracking-wider">
                {gettext("Theme")}
              </li>
              <li>
                <label class="flex items-center justify-between cursor-pointer">
                  <span>{gettext("Dark Mode")}</span>
                  <input
                    type="checkbox"
                    id="theme-toggle-dropdown"
                    phx-hook="ThemeToggle"
                    class="theme-controller toggle toggle-sm"
                    value="dark"
                  />
                </label>
              </li>

              <div class="divider my-1"></div>

              <li>
                <.link
                  href={~p"/staff/auth/log_out"}
                  method="delete"
                  class="text-error hover:bg-error/10 font-medium"
                >
                  {gettext("Log out")}
                </.link>
              </li>
            </ul>
          </div>
        <% end %>
      </div>
    </header>
    """
  end
end
