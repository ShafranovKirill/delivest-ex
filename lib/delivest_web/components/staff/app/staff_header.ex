defmodule DelivestWeb.StaffHeader do
  use DelivestWeb, :html

  import Delivest.Identity.Acl

  attr :current_staff, :map, default: nil
  attr :current_branch, :map, default: nil
  attr :new_orders_count, :integer, default: 0

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

      <.link navigate={~p"/staff/dashboard"} class="flex items-center gap-2 shrink-0">
        <img src={~p"/images/logo-dark.png"} alt="" class="size-8 object-contain dark:hidden" />
        <img src={~p"/images/logo-white.png"} alt="" class="size-8 object-contain hidden dark:block" />
        <span class="hidden sm:inline text-lg font-bold">Delivest</span>
      </.link>

      <div class="flex-1"></div>

      <.new_orders
        :if={@current_branch && can?(@current_staff, "orders.read")}
        count={@new_orders_count}
      />

      <.link
        :if={@current_branch && can?(@current_staff, "orders.create")}
        navigate={~p"/staff/orders/new"}
        class="btn btn-primary btn-sm"
        title={gettext("New Order")}
      >
        <.icon name="hero-plus" class="size-4" />
        <span class="hidden md:inline">{gettext("New Order")}</span>
      </.link>

      <.branch_selector current_branch={@current_branch} />
      <.theme_switch />
      <.staff_menu current_staff={@current_staff} />
    </header>
    """
  end

  attr :count, :integer, required: true

  defp new_orders(assigns) do
    ~H"""
    <.link
      id="header-new-orders"
      navigate={~p"/staff/orders?status=created"}
      class="btn btn-ghost btn-sm btn-square relative"
      title={gettext("Orders awaiting confirmation")}
    >
      <.icon name="hero-bell" class="size-5" />
      <span
        :if={@count > 0}
        id="header-new-orders-count"
        class="badge badge-error badge-xs absolute -top-1 -right-1 min-w-5 px-1 font-bold"
      >
        {@count}
      </span>
    </.link>
    """
  end

  defp theme_switch(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={JS.dispatch("phx:set-theme")}
      data-phx-theme="dark"
      class="btn btn-ghost btn-sm btn-square dark:hidden"
      title={gettext("Dark Mode")}
    >
      <.icon name="hero-moon" class="size-5" />
    </button>
    <button
      type="button"
      phx-click={JS.dispatch("phx:set-theme")}
      data-phx-theme="light"
      class="btn btn-ghost btn-sm btn-square hidden dark:inline-flex"
      title={gettext("Light Mode")}
    >
      <.icon name="hero-sun" class="size-5" />
    </button>
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
        class="flex items-center gap-3 cursor-pointer py-1 px-1 sm:px-2 rounded-xl hover:bg-base-200 transition-colors"
      >
        <div class="avatar placeholder">
          <div class="bg-primary text-primary-content rounded-xl w-10 h-10 flex items-center justify-center font-bold text-sm">
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

  defp branch_selector(assigns) do
    ~H"""
    <div class="dropdown dropdown-end">
      <div
        tabindex="0"
        role="button"
        class="flex items-center gap-2 h-10 cursor-pointer border border-base-300 py-1.5 px-2.5 sm:px-3 rounded-xl hover:bg-base-200 transition-colors min-w-0"
      >
        <.icon name="hero-building-storefront" class="h-4 w-4 text-base-content/70 shrink-0" />
        <span
          class="hidden sm:inline-block text-sm font-medium text-base-content truncate sm:max-w-75 lg:max-w-none align-middle"
          title={@current_branch && @current_branch.name}
        >
          <%= if @current_branch do %>
            {@current_branch.name}
          <% else %>
            <span class="font-semibold">{gettext("No branch selected")}</span>
          <% end %>
        </span>
      </div>

      <ul
        tabindex="0"
        class="dropdown-content z-1 menu p-2 shadow-lg bg-base-100 rounded-box w-56 border border-base-300 mt-2"
      >
        <li class="menu-title px-4 py-2 text-xs font-semibold text-base-content/50 uppercase tracking-wider">
          {gettext("Current Branch")}
        </li>
        <li class="px-4 py-1 text-xs text-base-content/70 wrap-break-word">
          <%= if @current_branch do %>
            {@current_branch.name}
          <% else %>
            {gettext("No branch selected")}
          <% end %>
        </li>
        <div class="divider my-1"></div>
        <li>
          <.link
            patch={~p"/staff/branches/select"}
            class="flex items-center gap-2 font-medium text-primary hover:bg-primary/10"
          >
            <.icon name="hero-arrow-path-rounded-square" class="h-4 w-4 shrink-0" />
            {gettext("Change branch")}
          </.link>
        </li>
      </ul>
    </div>
    """
  end
end
