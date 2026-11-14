defmodule DelivestWeb.StaffNav do
  use DelivestWeb, :html

  import Delivest.Identity.Acl

  alias Delivest.{Features, Gateway, Identity, Segments}

  def pages(staff, branch) do
    staff
    |> catalog(branch)
  end

  def active_setting(path) when is_binary(path) do
    cond do
      path == "/staff/settings" ->
        :features

      String.contains?(path, "/integrations/frontpad") ->
        :frontpad

      String.contains?(path, "/integrations/routes") ->
        :order_settings

      String.contains?(path, "/integrations") ->
        :integrations

      String.contains?(path, "/delivery/zones") ->
        :delivery_zones

      String.contains?(path, "/delivery") ->
        :delivery_settings

      String.contains?(path, "/branches/") and String.ends_with?(path, "/hours") ->
        :hours

      String.contains?(path, "/branches/") and String.ends_with?(path, "/snapshot") ->
        :site_snapshot

      String.contains?(path, "/branches/") and String.contains?(path, "/edit") ->
        :branch_settings

      path == "/staff/branches" ->
        :branches

      path == "/staff/franchise/snapshot" ->
        :instance_backup

      String.starts_with?(path, "/staff/franchise") ->
        :brand

      String.starts_with?(path, "/staff/roles") ->
        :roles_settings

      String.starts_with?(path, "/staff/employee") ->
        :team

      String.starts_with?(path, "/staff/diagnostics") or String.starts_with?(path, "/staff/logs") ->
        :data_system

      String.contains?(path, "/loyalty") ->
        :loyalty_settings

      true ->
        nil
    end
  end

  def active_setting(_), do: nil

  def feature_entry(key, staff) do
    {label, id} = feature_description(key)

    path =
      staff |> catalog(nil) |> Enum.find_value(fn entry -> if entry.id == id, do: entry.path end)

    %{label: label, path: path}
  end

  defp feature_description("segments"), do: {gettext("Segments"), :segments}
  defp feature_description("notifications"), do: {gettext("Notifications"), nil}

  defp feature_description("marketing_policies"),
    do: {gettext("Marketing policies"), :marketing_policies}

  defp feature_description("analytics_funnel"), do: {gettext("Sales funnel"), :statistics}
  defp feature_description("analytics_extended"), do: {gettext("Extended analytics"), :statistics}
  defp feature_description("analytics_franchise"), do: {gettext("Network analytics"), :statistics}
  defp feature_description("analytics_links"), do: {gettext("Advertising links"), :statistics}

  def integration_entry(provider, staff, branch) do
    label = integration_label(provider)

    path =
      cond do
        not can?(staff, "integrations.read") ->
          nil

        provider in [:zvonok, :dadata, :yookassa, :yandex_eda] and can?(staff, "admin") ->
          "/staff/integrations/#{provider_slug(provider)}"

        provider in [:zvonok, :dadata, :yookassa, :yandex_eda] ->
          nil

        is_nil(branch) ->
          nil

        true ->
          "/staff/b/#{branch.slug}/integrations/#{provider_slug(provider)}"
      end

    %{
      id: provider,
      label: label,
      path: path,
      scope:
        if(provider in [:zvonok, :dadata, :yookassa, :yandex_eda], do: :network, else: :branch)
    }
  end

  defp provider_slug(:yandex_eda), do: "yandex-eda"
  defp provider_slug(:yandex_delivery), do: "yandex-delivery"
  defp provider_slug(:atol), do: "fiscal"
  defp provider_slug(provider), do: Atom.to_string(provider)

  defp integration_label(:frontpad), do: gettext("Frontpad")
  defp integration_label(:iiko), do: gettext("iiko")
  defp integration_label(:rkeeper), do: gettext("r_keeper")
  defp integration_label(:zvonok), do: gettext("Phone sign-in")
  defp integration_label(:dadata), do: gettext("Address suggestions")
  defp integration_label(:yookassa), do: gettext("Online payment")
  defp integration_label(:yandex_eda), do: gettext("Yandex Eda")
  defp integration_label(:yandex_delivery), do: gettext("Yandex Delivery")
  defp integration_label(:atol), do: gettext("Fiscal receipts")

  def catalog(staff, branch) do
    legacy =
      staff
      |> legacy_entries(branch)
      |> Enum.flat_map(& &1.entries)
      |> Enum.flat_map(fn
        %{kind: :group, items: items} -> items
        item -> [item]
      end)

    (settings_entries(staff, branch) ++ menu_items(staff, branch) ++ legacy)
    |> Enum.uniq_by(& &1.id)
  end

  def menu_items(staff, branch) do
    if branch do
      products =
        if can?(staff, "products.read") do
          [
            item(:products, "/staff/b/#{branch.slug}/products", "hero-cube", gettext("Products")),
            item(
              :stops,
              "/staff/b/#{branch.slug}/products/stops",
              "hero-no-symbol",
              gettext("Stop list")
            ),
            item(
              :modifiers,
              "/staff/b/#{branch.slug}/products/modifiers",
              "hero-adjustments-horizontal",
              gettext("Modifiers")
            ),
            item(:tags, "/staff/b/#{branch.slug}/products/tags", "hero-tag", gettext("Tags")),
            item(
              :suggested,
              "/staff/b/#{branch.slug}/products/suggested",
              "hero-sparkles",
              gettext("Recommended")
            ),
            item(
              :popular,
              "/staff/b/#{branch.slug}/menu/popular",
              "hero-fire",
              gettext("Popular products")
            )
          ]
          |> Enum.map(&%{&1 | read_permissions: ["products.read"]})
        else
          []
        end

      categories =
        if can?(staff, "categories.read") do
          [
            item(
              :categories,
              "/staff/b/#{branch.slug}/categories",
              "hero-rectangle-stack",
              gettext("Categories")
            )
            |> Map.put(:read_permissions, ["categories.read"])
          ]
        else
          []
        end

      (products ++ categories)
      |> Enum.map(&%{&1 | parent: :menu})
    else
      []
    end
  end

  def entries(staff, branch), do: entries(staff, branch, branch)

  attr :staff, :map, required: true
  attr :branch, :any, default: nil
  attr :navigation_branch, :any, default: nil
  attr :current_page, :any, default: nil
  attr :current_path, :string, default: nil

  def local_navigation(assigns) do
    navigation_branch = assigns.navigation_branch || assigns.branch
    navigation_branch = navigation_branch && Delivest.Repo.preload(navigation_branch, :info)
    current_page = assigns.current_page

    group =
      assigns.staff
      |> entries(navigation_branch, navigation_branch)
      |> Enum.flat_map(& &1.entries)
      |> Enum.find(fn
        %{kind: :group, id: :marketing} when current_page == :marketing -> true
        %{kind: :group, items: items} -> Enum.any?(items, &(current_page in &1.pages))
        _ -> false
      end)

    items =
      cond do
        not is_nil(active_setting(assigns.current_path)) ->
          []

        assigns.current_page == :categories or
            not is_nil(DelivestWeb.Staff.ProductLive.ProductTags.section(assigns.current_path)) ->
          menu_items(assigns.staff, navigation_branch)

        assigns.current_page == :marketing ->
          marketing_entries(assigns.staff, navigation_branch)

        not is_nil(group) and
            assigns.current_page in [
              :deliveries,
              :couriers,
              :payments,
              :receipts,
              :clients,
              :segments,
              :marketing_policies,
              :stocks,
              :promotions,
              :loyalty,
              :advertising_links,
              :marketing
            ] ->
          group.items

        true ->
          []
      end

    assigns = assign(assigns, items: items)

    ~H"""
    <nav
      :if={@items != []}
      id="staff-section-navigation"
      phx-hook="ActiveSectionNav"
      aria-label={gettext("Page sections")}
      class="mb-5 flex gap-1 overflow-x-auto border-b border-base-300 pb-2"
    >
      <.link
        :for={item <- @items}
        id={
          if(item.parent == :menu,
            do: "product-section-tab-#{item.id}",
            else: "section-nav-#{item.id}"
          )
        }
        navigate={item.path}
        aria-current={active_local?(item, @current_page, @current_path) && "page"}
        class={[
          "whitespace-nowrap rounded-field px-3 py-2 text-sm hover:bg-base-200",
          active_local?(item, @current_page, @current_path) && "bg-base-200 font-semibold"
        ]}
      >
        {item.label}
      </.link>
    </nav>
    """
  end

  defp active_local?(%{page_type: :settings} = item, _page, path),
    do: active_setting(path) == item.id

  defp active_local?(%{parent: :menu} = item, page, path) do
    current = DelivestWeb.Staff.ProductLive.ProductTags.section(path)
    item.id == if(current == :bulk, do: :products, else: current || page)
  end

  defp active_local?(item, page, _path), do: page in item.pages

  def entries(staff, branch, marketing_branch) do
    raw = legacy_entries(staff, branch, marketing_branch)

    items =
      raw
      |> Enum.flat_map(& &1.entries)
      |> Enum.flat_map(fn
        %{kind: :group, items: children} -> children
        item -> [item]
      end)

    find = fn id -> Enum.find(items, &(&1.id == id)) end

    top = fn id, label, icon, children ->
      case Enum.reject(children, &is_nil/1) do
        [] -> nil
        [only] when id != :settings -> %{only | label: label, icon: icon, pages: only.pages}
        available -> %{kind: :group, id: id, label: label, icon: icon, items: available}
      end
    end

    main =
      [
        primary_label(find.(:dashboard), gettext("Overview")),
        top.(
          :orders,
          gettext("Orders"),
          "hero-shopping-bag",
          Enum.map([:orders, :orders_new, :pos, :kitchen], find)
        ),
        top.(
          :delivery,
          gettext("Delivery"),
          "hero-map",
          Enum.map([:deliveries, :couriers], find) ++
            [Enum.find(settings_entries(staff, branch), &(&1.id == :delivery_zones))]
        ),
        top.(:menu, gettext("Menu"), "hero-book-open", Enum.map([:products, :categories], find)),
        top.(:customers, gettext("Clients"), "hero-users", Enum.map([:clients, :segments], find)),
        top.(
          :marketing,
          gettext("Marketing"),
          "hero-megaphone",
          Enum.map(
            [:marketing_policies, :stocks, :promotions, :loyalty, :advertising_links],
            find
          )
        ),
        top.(
          :finance,
          gettext("Finance"),
          "hero-banknotes",
          Enum.map([:payments, :receipts], find)
        ),
        primary_label(find.(:statistics), gettext("Analytics"))
      ]
      |> Enum.reject(&is_nil/1)

    [
      section(:main, nil, main),
      section(:settings, nil, Enum.reject([find.(:settings)], &is_nil/1))
    ]
    |> Enum.reject(&(&1.entries == []))
  end

  defp legacy_entries(staff, branch), do: legacy_entries(staff, branch, branch)

  defp primary_label(nil, _label), do: nil
  defp primary_label(item, label), do: %{item | label: label}

  defp legacy_entries(staff, branch, marketing_branch) do
    [
      section(:branch, branch && branch.name, branch_entries(staff, branch)),
      section(
        :network,
        gettext("Network"),
        common_entries(staff, marketing_branch) ++ network_entries(staff)
      )
    ]
    |> Enum.reject(&(&1.entries == []))
  end

  def settings_entries(staff, branch) do
    [
      setting(:settings, gettext("Settings"), "/staff/settings", "hero-cog-6-tooth", :network, [
        "franchise.update",
        "branches.read",
        "delivery.read",
        "integrations.read"
      ]),
      setting(
        :features,
        gettext("Features and connections"),
        "/staff/settings",
        "hero-squares-plus",
        :network,
        ["franchise.update", "branches.read", "delivery.read", "integrations.read"]
      ),
      setting(
        :brand,
        gettext("Network and brand"),
        "/staff/franchise/brand",
        "hero-building-storefront",
        :network,
        ["franchise.update"],
        [gettext("brand"), gettext("logo")]
      ),
      setting(:branches, gettext("Branches"), "/staff/branches", "hero-map-pin", :network, [
        "branches.read",
        "delivery.read"
      ]),
      setting(
        :branch_settings,
        gettext("Branch operation"),
        branch && "/staff/branches/#{branch.slug}/edit",
        "hero-building-storefront",
        :branch,
        ["branches.read", "delivery.read"]
      ),
      setting(
        :hours,
        gettext("Working Hours"),
        branch && "/staff/branches/#{branch.slug}/edit/hours",
        "hero-clock",
        :branch,
        ["branches.read", "delivery.read"],
        [gettext("schedule"), "график", "часы работы"]
      ),
      setting(
        :delivery_settings,
        gettext("Delivery"),
        branch && "/staff/b/#{branch.slug}/delivery",
        "hero-map",
        :branch,
        ["delivery.read"],
        []
      ),
      setting(
        :delivery_zones,
        gettext("Delivery zones"),
        branch && "/staff/b/#{branch.slug}/delivery/zones",
        "hero-map-pin",
        :branch,
        ["delivery.read"],
        ["зоны", "зоны доставки"]
      ),
      setting(
        :order_settings,
        gettext("Orders and payment"),
        branch && "/staff/b/#{branch.slug}/integrations/routes",
        "hero-credit-card",
        :branch,
        ["integrations.read"],
        []
      ),
      setting(
        :loyalty_settings,
        gettext("Loyalty"),
        branch && "/staff/b/#{branch.slug}/loyalty",
        "hero-star",
        :branch,
        ["promotions.read"],
        ["бонусы", gettext("bonuses")]
      ),
      setting(
        :integrations,
        gettext("Integrations"),
        if(branch, do: "/staff/b/#{branch.slug}/integrations", else: "/staff/integrations"),
        "hero-puzzle-piece",
        :mixed,
        ["integrations.read"]
      ),
      setting(
        :frontpad,
        gettext("Frontpad"),
        branch && "/staff/b/#{branch.slug}/integrations/frontpad",
        "hero-puzzle-piece",
        :branch,
        ["integrations.read"],
        ["фронтпад", "отправка заказов"]
      ),
      setting(
        :team,
        gettext("Team and access"),
        "/staff/employee",
        "hero-user-group",
        :network,
        ["staff.read"],
        ["сотрудники"]
      ),
      setting(
        :roles_settings,
        gettext("Roles and permissions"),
        "/staff/roles",
        "hero-shield-check",
        :network,
        ["roles.read"],
        ["права"]
      ),
      setting(
        :data_system,
        gettext("Data and system"),
        "/staff/diagnostics",
        "hero-beaker",
        :network,
        ["logs.read"],
        ["диагностика"]
      ),
      setting(
        :site_snapshot,
        gettext("Site snapshot"),
        branch && "/staff/branches/#{branch.slug}/edit/snapshot",
        "hero-archive-box-arrow-down",
        :branch,
        ["branches.update"],
        ["слепок витрины"]
      ),
      setting(
        :instance_backup,
        gettext("Instance backup"),
        "/staff/franchise/snapshot",
        "hero-archive-box-arrow-down",
        :network,
        ["admin"],
        ["полный слепок", "резервная копия"]
      )
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(fn entry -> Enum.any?(entry.read_permissions, &can?(staff, &1)) end)
  end

  defp setting(id, label, path, icon, scope, permissions, aliases \\ [])

  defp setting(_id, _label, nil, _icon, _scope, _permissions, _aliases), do: nil

  defp setting(id, label, path, icon, scope, permissions, aliases) do
    %{
      kind: :item,
      id: id,
      page: id,
      pages: [id],
      parent: :settings,
      page_type: :settings,
      scope: scope,
      path: path,
      route: fn selected_branch -> setting_path(id, selected_branch) end,
      icon: icon,
      label: label,
      read_permissions: permissions,
      edit_permissions: [],
      feature: nil,
      switch_rule: if(scope == :branch, do: :same_section, else: :network),
      aliases: aliases
    }
  end

  defp setting_path(:settings, _), do: "/staff/settings"
  defp setting_path(:features, _), do: "/staff/settings"
  defp setting_path(:brand, _), do: "/staff/franchise/brand"
  defp setting_path(:branches, _), do: "/staff/branches"
  defp setting_path(:team, _), do: "/staff/employee"
  defp setting_path(:roles_settings, _), do: "/staff/roles"
  defp setting_path(:data_system, _), do: "/staff/diagnostics"
  defp setting_path(:instance_backup, _), do: "/staff/franchise/snapshot"
  defp setting_path(:integrations, nil), do: "/staff/integrations"
  defp setting_path(:integrations, branch), do: "/staff/b/#{branch.slug}/integrations"
  defp setting_path(_id, nil), do: nil
  defp setting_path(:branch_settings, branch), do: "/staff/branches/#{branch.slug}/edit"
  defp setting_path(:hours, branch), do: "/staff/branches/#{branch.slug}/edit/hours"
  defp setting_path(:delivery_settings, branch), do: "/staff/b/#{branch.slug}/delivery"
  defp setting_path(:delivery_zones, branch), do: "/staff/b/#{branch.slug}/delivery/zones"
  defp setting_path(:order_settings, branch), do: "/staff/b/#{branch.slug}/integrations/routes"
  defp setting_path(:loyalty_settings, branch), do: "/staff/b/#{branch.slug}/loyalty"
  defp setting_path(:frontpad, branch), do: "/staff/b/#{branch.slug}/integrations/frontpad"
  defp setting_path(:site_snapshot, branch), do: "/staff/branches/#{branch.slug}/edit/snapshot"

  defp branch_entries(staff, branch) do
    [
      item(
        :dashboard,
        if(branch, do: ~p"/staff/b/#{branch}/dashboard", else: ~p"/staff/dashboard"),
        "hero-squares-2x2",
        gettext("Dashboard")
      ),
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
        |> allowed(staff, "orders.read"),
        item(
          :pos,
          branch && ~p"/staff/b/#{branch}/pos",
          "hero-calculator",
          gettext("POS")
        )
        |> allowed(staff, "pos.use")
        |> owned(branch, :pos),
        item(
          :kitchen,
          branch && ~p"/staff/b/#{branch}/kitchen",
          "hero-fire",
          gettext("Kitchen")
        )
        |> allowed(staff, "orders.cook")
        |> operating(branch),
        item(
          :deliveries,
          branch && ~p"/staff/b/#{branch}/deliveries",
          "hero-map",
          gettext("Deliveries")
        )
        |> allowed(staff, "orders.deliver")
        |> owned(branch, :couriers),
        item(
          :couriers,
          branch && ~p"/staff/b/#{branch}/couriers",
          "hero-user-circle",
          gettext("Couriers")
        )
        |> allowed(staff, "orders.update")
        |> owned(branch, :couriers)
      ]),
      group(:finance, "hero-banknotes", gettext("Finance"), [
        item(
          :payments,
          branch && ~p"/staff/b/#{branch}/finance/transactions",
          "hero-credit-card",
          gettext("Payments")
        )
        |> allowed(staff, "finance.read"),
        item(
          :receipts,
          branch && ~p"/staff/b/#{branch}/finance/receipts",
          "hero-document-text",
          gettext("Receipts")
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
        |> covering([:tags, :suggested, :popular, :stops])
        |> allowed(staff, "products.read")
      ])
    ]
    |> compact_all()
  end

  defp common_entries(staff, branch) do
    [
      item(:statistics, ~p"/staff/statistics", "hero-chart-bar", gettext("Statistics"))
      |> allowed(staff, "statistics.read"),
      group(:marketing, "hero-megaphone", gettext("Marketing"), marketing_entries(staff, branch))
    ]
    |> compact_all()
  end

  defp marketing_entries(staff, branch) do
    available_branches =
      if(branch, do: [branch], else: Identity.list_branch_for_staff(staff))
      |> Delivest.Repo.preload(:info)

    bonus_branches = Identity.list_branch_for_staff(staff) |> Delivest.Repo.preload(:info)

    [
      item(
        :marketing_policies,
        global_marketing_path(:policies, branch),
        "hero-rectangle-stack",
        gettext("Marketing policies")
      )
      |> then(fn item ->
        if can?(staff, "marketing.read") and Features.enabled?("marketing_policies", :franchise),
          do: %{item | read_permissions: ["marketing.read"], feature: "marketing_policies"}
      end),
      item(:stocks, marketing_path(branch, "stocks"), "hero-photo", gettext("Banners"))
      |> allowed(staff, "stocks.read")
      |> available_in(available_branches, fn _ -> true end),
      item(
        :promotions,
        marketing_path(branch, "promotions"),
        "hero-receipt-percent",
        gettext("Discounts & promo codes")
      )
      |> allowed(staff, "promotions.read")
      |> available_in(available_branches, fn _ -> true end),
      item(:loyalty, global_marketing_path(:bonuses, branch), "hero-star", gettext("Bonuses"))
      |> then(fn item ->
        if can?(staff, "franchise.update") or
             Enum.any?(bonus_branches, fn branch ->
               Identity.authorize(staff, "promotions.read", branch.id) == :ok and
                 Gateway.own?(branch, :loyalty)
             end),
           do: item
      end),
      item(
        :advertising_links,
        marketing_path(branch, "links"),
        "hero-link",
        gettext("Advertising links")
      )
      |> allowed(staff, "statistics.read")
      |> with_feature("analytics_links")
      |> available_in(available_branches, &Features.enabled?("analytics_links", {:branch, &1.id}))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp global_marketing_path(:policies, nil), do: ~p"/staff/marketing/policies"
  defp global_marketing_path(:bonuses, nil), do: ~p"/staff/marketing/bonuses"

  defp global_marketing_path(:policies, branch),
    do: ~p"/staff/marketing/policies?#{%{branch: branch.slug}}"

  defp global_marketing_path(:bonuses, branch),
    do: ~p"/staff/marketing/bonuses?#{%{branch: branch.slug}}"

  defp marketing_path(nil, section), do: ~p"/staff/marketing?#{%{section: section}}"
  defp marketing_path(branch, "stocks"), do: ~p"/staff/b/#{branch}/stocks"
  defp marketing_path(branch, "promotions"), do: ~p"/staff/b/#{branch}/promotions"
  defp marketing_path(branch, "loyalty"), do: ~p"/staff/b/#{branch}/loyalty"
  defp marketing_path(branch, "links"), do: ~p"/staff/b/#{branch}/advertising-links"

  defp available_in(nil, _branches, _filter), do: nil
  defp available_in(item, branches, filter), do: if(Enum.any?(branches, filter), do: item)

  defp network_entries(staff) do
    [
      group(:customers, "hero-users", gettext("Clients"), [
        item(:clients, ~p"/staff/clients", "hero-users", gettext("Clients"))
        |> allowed(staff, "clients.read"),
        item(:segments, ~p"/staff/segments", "hero-user-group", gettext("Segments"))
        |> allowed(staff, "segments.read")
        |> with_feature("segments")
        |> then(fn item -> if Segments.available?(staff), do: item end)
      ]),
      group(:people, "hero-user-group", gettext("Team"), [
        item(:employee, ~p"/staff/employee", "hero-user-group", gettext("Staff"))
        |> allowed(staff, "staff.read"),
        item(:roles, ~p"/staff/roles", "hero-shield-check", gettext("Roles"))
        |> allowed(staff, "roles.read")
      ]),
      group(:diagnostics, "hero-beaker", gettext("Diagnostics"), [
        item(:logs, ~p"/staff/logs", "hero-document-magnifying-glass", gettext("Logs"))
        |> allowed(staff, "logs.read"),
        item(:metrics, ~p"/staff/diagnostics", "hero-chart-bar", gettext("Metrics"))
        |> allowed(staff, "logs.read")
      ]),
      item(:settings, ~p"/staff/settings", "hero-cog-6-tooth", gettext("Settings"))
      |> then(fn item ->
        if Enum.any?(
             ~w(franchise.update branches.read delivery.read integrations.read),
             &can?(staff, &1)
           ),
           do: covering(item, [:branches, :integrations, :delivery])
      end)
    ]
    |> compact_all()
  end

  defp compact_all(entries), do: entries |> Enum.map(&compact/1) |> Enum.reject(&is_nil/1)

  defp compact(%{kind: :group, id: :marketing, items: items} = group) do
    case Enum.reject(items, &is_nil/1) do
      [] -> nil
      items -> %{group | items: items}
    end
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
    do: %{
      kind: :item,
      id: page,
      page: page,
      pages: [page],
      parent: nil,
      page_type: :page,
      scope: if(String.starts_with?(path, "/staff/b/"), do: :branch, else: :network),
      path: path,
      route: fn target_scope -> route_for(path, target_scope) end,
      icon: icon,
      label: label,
      read_permissions: [],
      edit_permissions: [],
      feature: nil,
      switch_rule: :same_section,
      aliases: []
    }

  defp covering(nil, _pages), do: nil
  defp covering(item, pages), do: %{item | pages: [item.page | pages]}

  defp section(id, label, entries), do: %{id: id, label: label, entries: entries}

  defp group(id, icon, label, items),
    do: %{kind: :group, id: id, icon: icon, label: label, items: items}

  defp owned(nil, _branch, _area), do: nil
  defp owned(item, nil, area), do: %{item | feature: {:gateway, area}}

  defp owned(item, branch, area),
    do: if(Gateway.own?(branch, area), do: %{item | feature: {:gateway, area}})

  defp operating(nil, _branch), do: nil
  defp operating(item, nil), do: item
  defp operating(item, branch), do: if(Delivest.Oms.Kitchen.working?(branch), do: item)

  defp allowed(nil, _staff, _permission), do: nil

  defp allowed(item, staff, permission),
    do: if(can?(staff, permission), do: %{item | read_permissions: [permission]})

  defp with_feature(nil, _feature), do: nil
  defp with_feature(item, feature), do: %{item | feature: feature}

  defp route_for(path, nil) do
    case DelivestWeb.StaffBranchPath.transition(path, :network) do
      {:ok, %{path: target}} -> target
      _ -> nil
    end
  end

  defp route_for(path, branch) do
    case DelivestWeb.StaffBranchPath.transition(path, {:branch, branch.slug}) do
      {:ok, %{path: target}} -> target
      _ -> nil
    end
  end
end
