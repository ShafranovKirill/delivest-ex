defmodule DelivestWeb.StaffSidebar do
  use DelivestWeb, :html

  import Delivest.Identity.Acl

  attr :current_page, :atom, default: nil
  attr :current_staff, :map, default: nil
  attr :current_branch, :map, default: nil

  def staff_sidebar(assigns) do
    assigns = assign(assigns, entries: entries(assigns.current_staff, assigns.current_branch))

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
        <div class="flex flex-col gap-1">
          <%= for entry <- @entries do %>
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
      assign(assigns, active: Enum.any?(assigns.group.items, &(&1.page == assigns.current_page)))

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
        @current_page == @item.page && "menu-active"
      ]}
    >
      <.icon name={@item.icon} class="size-6 shrink-0" />
      <span class="font-bold truncate lg:sidebar-collapsed:hidden">{@item.label}</span>
    </.link>
    """
  end

  defp entries(staff, branch) do
    [
      item(
        :dashboard,
        branch && ~p"/staff/b/#{branch}/dashboard",
        "hero-squares-2x2",
        gettext("Dashboard")
      ),
      item(
        :statistics,
        branch && ~p"/staff/b/#{branch}/statistics",
        "hero-chart-bar",
        gettext("Statistics")
      )
      |> allowed(staff, "statistics.read"),
      group(:orders, "hero-shopping-bag", gettext("Orders"), [
        item(
          :orders_new,
          branch && ~p"/staff/b/#{branch}/orders/new",
          "hero-plus-circle",
          gettext("New Order")
        )
        |> allowed(staff, "orders.create"),
        item(
          :orders,
          branch && ~p"/staff/b/#{branch}/orders",
          "hero-queue-list",
          gettext("All orders")
        )
        |> allowed(staff, "orders.read")
      ]),
      group(:menu, "hero-book-open", gettext("Menu"), [
        item(
          :categories,
          branch && ~p"/staff/b/#{branch}/categories",
          "hero-rectangle-stack",
          gettext("Categories")
        )
        |> allowed(staff, "categories.read"),
        item(
          :products,
          branch && ~p"/staff/b/#{branch}/products",
          "hero-cube",
          gettext("Products")
        )
        |> allowed(staff, "products.read"),
        item(
          :stops,
          branch && ~p"/staff/b/#{branch}/products/stops",
          "hero-no-symbol",
          gettext("Stop list")
        )
        |> allowed(staff, "products.read"),
        item(:tags, branch && ~p"/staff/b/#{branch}/products/tags", "hero-tag", gettext("Tags"))
        |> allowed(staff, "products.read"),
        item(
          :suggested,
          branch && ~p"/staff/b/#{branch}/products/suggested",
          "hero-sparkles",
          gettext("Recommended")
        )
        |> allowed(staff, "products.read")
      ]),
      group(:marketing, "hero-megaphone", gettext("Marketing"), [
        item(:stocks, branch && ~p"/staff/b/#{branch}/stocks", "hero-photo", gettext("Banners"))
        |> allowed(staff, "stocks.read"),
        item(
          :promotions,
          branch && ~p"/staff/b/#{branch}/promotions",
          "hero-receipt-percent",
          gettext("Discounts & promo codes")
        )
        |> allowed(staff, "promotions.read")
      ]),
      group(:company, "hero-building-office-2", gettext("Company"), [
        item(:branches, ~p"/staff/branches", "hero-map-pin", gettext("Branches"))
        |> allowed(staff, "branches.read"),
        item(
          :delivery,
          branch && ~p"/staff/b/#{branch}/delivery",
          "hero-truck",
          gettext("Delivery")
        )
        |> allowed(staff, "delivery.read"),
        item(:clients, ~p"/staff/clients", "hero-users", gettext("Clients"))
        |> allowed(staff, "clients.read"),
        item(
          :franchise,
          ~p"/staff/franchise",
          "hero-building-storefront",
          gettext("Franchise settings")
        )
        |> allowed(staff, "franchise.update")
      ]),
      group(:people, "hero-user-group", gettext("Team"), [
        item(:employee, ~p"/staff/employee", "hero-user-group", gettext("Staff"))
        |> allowed(staff, "staff.read"),
        item(:roles, ~p"/staff/roles", "hero-shield-check", gettext("Roles"))
        |> allowed(staff, "roles.read")
      ]),
      group(:system, "hero-cog-6-tooth", gettext("System"), [
        item(
          :integrations,
          branch && ~p"/staff/b/#{branch}/integrations",
          "hero-puzzle-piece",
          gettext("Integrations")
        )
        |> allowed(staff, "integrations.read"),
        item(:logs, ~p"/staff/logs", "hero-document-magnifying-glass", gettext("Logs"))
        |> allowed(staff, "logs.read")
      ])
    ]
    |> Enum.map(&compact/1)
    |> Enum.reject(&is_nil/1)
  end

  defp compact(%{kind: :group, items: items} = group) do
    case Enum.reject(items, &is_nil/1) do
      [] -> nil
      [item] -> item
      items -> %{group | items: items}
    end
  end

  defp compact(entry), do: entry

  defp item(_page, nil, _icon, _label), do: nil

  defp item(page, path, icon, label),
    do: %{kind: :item, page: page, path: path, icon: icon, label: label}

  defp group(id, icon, label, items),
    do: %{kind: :group, id: id, icon: icon, label: label, items: items}

  defp allowed(item, staff, permission), do: if(can?(staff, permission), do: item)
end
