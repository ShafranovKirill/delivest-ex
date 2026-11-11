defmodule DelivestWeb.StaffProfileMenu do
  use DelivestWeb, :html

  import Delivest.Identity.Acl

  attr :current_staff, :map, required: true

  def staff_profile_menu(assigns) do
    staff_name =
      if assigns.current_staff.name in [nil, ""],
        do: gettext("Staff"),
        else: assigns.current_staff.name

    assigns =
      assigns
      |> assign(:staff_name, staff_name)
      |> assign(:initial, staff_name |> String.first() |> String.upcase())
      |> assign(:current_locale, Gettext.get_locale(DelivestWeb.Gettext))

    ~H"""
    <div id="staff-profile" class="staff-profile relative min-w-0 flex-1">
      <button
        id="staff-profile-trigger"
        type="button"
        data-profile-trigger
        aria-haspopup="true"
        aria-controls="staff-profile-menu"
        aria-expanded="false"
        aria-label={gettext("Profile: %{name}", name: @staff_name)}
        title={@staff_name}
        class="staff-profile-trigger flex w-full min-w-0 items-center gap-2 rounded-field p-1 text-left hover:bg-base-200"
      >
        <span class="flex size-8 shrink-0 items-center justify-center rounded-field bg-primary text-sm font-bold text-primary-content">
          {@initial}
        </span>
        <span class="staff-sidebar-label min-w-0 flex-1">
          <span class="block truncate text-sm font-semibold leading-tight">{@staff_name}</span>
          <span class="block truncate text-xs text-base-content/60">{@current_staff.role.name}</span>
        </span>
        <.icon
          name="hero-chevron-up"
          class="staff-sidebar-label staff-profile-chevron size-4 shrink-0 text-base-content/55"
        />
      </button>

      <ul
        id="staff-profile-menu"
        data-profile-menu
        hidden
        class="staff-profile-menu menu rounded-box border border-base-300 bg-base-100 p-2 shadow-xl"
      >
        <li class="menu-title">{gettext("Language")}</li>
        <li>
          <.link :if={@current_locale == "ru"} href={~p"/locale/en"}>🇬🇧 English</.link>
          <.link :if={@current_locale != "ru"} href={~p"/locale/ru"}>🇷🇺 Русский</.link>
        </li>
        <li :if={can?(@current_staff, "orders.read")} class="menu-title">{gettext("New orders")}</li>
        <li :if={can?(@current_staff, "orders.read")}>
          <DelivestWeb.OrderSoundToggle.order_sound_toggle />
        </li>
        <li class="menu-title">{gettext("This device")}</li>
        <li><DelivestWeb.StaffPushToggle.staff_push_toggle id="header-push-toggle" /></li>
        <li class="menu-title">{gettext("Theme")}</li>
        <li class="dark:hidden">
          <button
            id="header-theme-dark"
            type="button"
            phx-click={JS.dispatch("phx:set-theme")}
            data-phx-theme="dark"
          >
            <.icon name="hero-moon" class="size-4" /> {gettext("Dark Mode")}
          </button>
        </li>
        <li class="hidden dark:block">
          <button
            id="header-theme-light"
            type="button"
            phx-click={JS.dispatch("phx:set-theme")}
            data-phx-theme="light"
          >
            <.icon name="hero-sun" class="size-4" /> {gettext("Light Mode")}
          </button>
        </li>
        <li>
          <.link
            href={~p"/staff/auth/log_out"}
            method="delete"
            class="text-error hover:bg-error/10 font-medium"
          >
            {gettext("Log out")}
          </.link>
        </li>
        <li
          id="app-version"
          class="border-t border-base-300 px-3 pt-2 text-xs font-mono text-base-content/40"
        >
          v{Application.get_env(:delivest, :version, "dev")}
        </li>
      </ul>
    </div>
    """
  end
end
