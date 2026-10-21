defmodule DelivestWeb.StaffSidebar do
  use DelivestWeb, :html

  import Delivest.Identity.Acl

  attr :current_page, :atom, default: nil
  attr :current_staff, :map, default: nil

  def staff_sidebar(assigns) do
    assigns = assign(assigns, sections: sections(assigns.current_staff))

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
        <.nav_section
          :for={{title, items} <- @sections}
          title={title}
          items={items}
          current_page={@current_page}
        />
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

  attr :title, :string, default: nil
  attr :items, :list, required: true
  attr :current_page, :atom, default: nil

  defp nav_section(assigns) do
    ~H"""
    <div :if={@title} class="pt-4 pb-1 first:pt-0">
      <div class="hidden h-px bg-base-300 mx-2 lg:sidebar-collapsed:block"></div>
      <p class="px-3 text-[10px] font-black uppercase tracking-widest text-base-content/50 lg:sidebar-collapsed:hidden">
        {@title}
      </p>
    </div>
    <ul class="menu w-full p-0 gap-1">
      <li :for={item <- @items}>
        <.link
          navigate={item.path}
          title={item.label}
          class={[
            "flex items-center gap-2 px-3 py-2",
            "lg:sidebar-collapsed:justify-center lg:sidebar-collapsed:px-2",
            @current_page == item.page && "menu-active"
          ]}
        >
          <.icon name={item.icon} class="size-6 shrink-0" />
          <span class="font-bold truncate lg:sidebar-collapsed:hidden">{item.label}</span>
        </.link>
      </li>
    </ul>
    """
  end

  defp sections(staff) do
    [
      {nil, [item(:dashboard, ~p"/staff/dashboard", "hero-squares-2x2", gettext("Dashboard"))]},
      {gettext("Analytics"),
       [
         item(:statistics, ~p"/staff/statistics", "hero-chart-bar", gettext("Statistics"))
         |> allowed(staff, "statistics.read")
       ]},
      {gettext("OMS"),
       [
         item(:orders_new, ~p"/staff/orders/new", "hero-plus-circle", gettext("New Order"))
         |> allowed(staff, "orders.create"),
         item(:orders, ~p"/staff/orders", "hero-shopping-bag", gettext("Orders"))
         |> allowed(staff, "orders.read")
       ]},
      {gettext("Catalog"),
       [
         item(:categories, ~p"/staff/categories", "hero-rectangle-stack", gettext("Categories"))
         |> allowed(staff, "categories.read"),
         item(:products, ~p"/staff/products", "hero-cube", gettext("Products"))
         |> allowed(staff, "products.read"),
         item(:stocks, ~p"/staff/stocks", "hero-tag", gettext("Promotions"))
         |> allowed(staff, "stocks.read"),
         item(
           :promotions,
           ~p"/staff/promotions",
           "hero-receipt-percent",
           gettext("Discounts & promo codes")
         )
         |> allowed(staff, "promotions.read")
       ]},
      {gettext("Company"),
       [
         item(:branches, ~p"/staff/branches", "hero-map-pin", gettext("Branches"))
         |> allowed(staff, "branches.read"),
         item(:clients, ~p"/staff/clients", "hero-users", gettext("Clients"))
         |> allowed(staff, "clients.read"),
         item(:employee, ~p"/staff/employee", "hero-user-group", gettext("Staff"))
         |> allowed(staff, "staff.read"),
         item(:roles, ~p"/staff/roles", "hero-shield-check", gettext("Roles"))
         |> allowed(staff, "roles.read"),
         item(
           :franchise,
           ~p"/staff/franchise",
           "hero-building-storefront",
           gettext("Franchise settings")
         )
         |> allowed(staff, "admin")
       ]},
      {gettext("System"),
       [
         item(
           :integrations,
           ~p"/staff/integrations",
           "hero-puzzle-piece",
           gettext("Integrations")
         )
         |> allowed(staff, "branches.read"),
         item(:logs, ~p"/staff/logs", "hero-document-magnifying-glass", gettext("Logs"))
         |> allowed(staff, "logs.read")
       ]}
    ]
    |> Enum.map(fn {title, items} -> {title, Enum.reject(items, &is_nil/1)} end)
    |> Enum.reject(fn {_title, items} -> items == [] end)
  end

  defp item(page, path, icon, label), do: %{page: page, path: path, icon: icon, label: label}

  defp allowed(item, staff, permission), do: if(can?(staff, permission), do: item)
end
