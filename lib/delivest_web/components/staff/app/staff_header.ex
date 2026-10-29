defmodule DelivestWeb.StaffHeader do
  use DelivestWeb, :html

  import Delivest.Identity.Acl

  attr :current_staff, :map, default: nil
  attr :current_branch, :map, default: nil
  attr :staff_branches, :list, default: []
  attr :current_path, :string, default: nil
  attr :new_orders_count, :integer, default: 0
  attr :kitchen_status, :any, default: nil

  def staff_header(assigns) do
    ~H"""
    <header class="fixed inset-x-0 top-0 z-50 flex h-16 items-center gap-2 border-b border-base-300 bg-base-100 px-3 sm:gap-3 sm:px-5">
      <button
        type="button"
        phx-click={JS.dispatch("sidebar:toggle-open")}
        class="btn btn-ghost btn-square btn-sm lg:hidden"
        aria-label={gettext("Open menu")}
      >
        <.icon name="hero-bars-3" class="size-6" />
      </button>

      <.link
        navigate={DelivestWeb.StaffBranchPath.home(@current_branch)}
        class="hidden sm:flex items-center gap-2 shrink-0"
      >
        <img src={~p"/images/logo-dark.png"} alt="" class="size-8 object-contain dark:hidden" />
        <img src={~p"/images/logo-white.png"} alt="" class="size-8 object-contain hidden dark:block" />
        <span class="text-lg font-bold">Delivest</span>
      </.link>

      <div class="flex flex-1 justify-end sm:justify-center">
        <DelivestWeb.CommandPalette.command_palette_trigger />
      </div>

      <DelivestWeb.KitchenControl.kitchen_indicator status={@kitchen_status} />

      <DelivestWeb.NewOrdersBell.new_orders_bell
        :if={@current_branch && can?(@current_staff, "orders.read")}
        count={@new_orders_count}
        branch={@current_branch}
      />

      <DelivestWeb.BranchSwitcher.branch_switcher
        current_branch={@current_branch}
        branches={@staff_branches}
        section={DelivestWeb.StaffBranchPath.section(@current_path)}
      />
      <.staff_menu current_staff={@current_staff} />
    </header>
    """
  end

  defp staff_menu(assigns) do
    ~H"""
    <% current_locale = Gettext.get_locale(DelivestWeb.Gettext) %>
    <% staff_name =
      if @current_staff.name && @current_staff.name != "",
        do: @current_staff.name,
        else: gettext("Staff") %>
    <% initial = String.first(staff_name) |> String.upcase() %>

    <div class="dropdown dropdown-end">
      <div
        tabindex="0"
        role="button"
        class="flex items-center gap-3 cursor-pointer py-1 px-1 sm:px-2 rounded-field hover:bg-base-200 transition-colors"
      >
        <div class="avatar placeholder">
          <div class="bg-primary text-primary-content rounded-field w-10 h-10 flex items-center justify-center font-bold text-sm">
            <span>{initial}</span>
          </div>
        </div>
        <div class="hidden sm:flex flex-col text-left">
          <span class="text-sm font-semibold text-base-content leading-tight">{staff_name}</span>
          <span class="text-xs text-base-content/60 leading-tight mt-0.5">{@current_staff.role.name}</span>
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
            <.link href={~p"/locale/en"} class="flex items-center justify-between"><span>🇬🇧 English</span></.link>
          <% else %>
            <.link href={~p"/locale/ru"} class="flex items-center justify-between"><span>🇷🇺 Русский</span></.link>
          <% end %>
        </li>

        <div :if={can?(@current_staff, "orders.read")} class="divider my-1"></div>

        <li
          :if={can?(@current_staff, "orders.read")}
          class="menu-title px-4 py-2 text-xs font-semibold text-base-content/50 uppercase tracking-wider"
        >
          {gettext("New orders")}
        </li>
        <li :if={can?(@current_staff, "orders.read")}>
          <DelivestWeb.OrderSoundToggle.order_sound_toggle />
        </li>

        <div class="divider my-1"></div>

        <li class="menu-title px-4 py-2 text-xs font-semibold text-base-content/50 uppercase tracking-wider">
          {gettext("This device")}
        </li>
        <li>
          <DelivestWeb.StaffPushToggle.staff_push_toggle id="header-push-toggle" />
        </li>

        <div class="divider my-1"></div>

        <li class="menu-title px-4 py-2 text-xs font-semibold text-base-content/50 uppercase tracking-wider">
          {gettext("Theme")}
        </li>
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
    """
  end
end
