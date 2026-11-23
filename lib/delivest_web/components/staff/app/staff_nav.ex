defmodule DelivestWeb.StaffNav do
  use DelivestWeb, :html

  import Delivest.Identity.Acl

  alias Delivest.{Couriers, Features, Gateway, Identity, Segments}

  def pages(staff, branch) do
    staff
    |> catalog(branch)
  end

  def active_setting(path) when is_binary(path) do
    cond do
      path == "/staff/settings" ->
        :features

      path in ["/staff/settings/data-transfer", "/staff/settings/data-system"] ->
        :data_system

      String.contains?(path, "/integrations/routes") ->
        :integrations

      String.contains?(path, "/integrations") ->
        :integrations

      String.contains?(path, "/delivery/zones") ->
        :branches

      String.contains?(path, "/delivery") ->
        :branches

      String.contains?(path, "/branches/") and String.ends_with?(path, "/hours") ->
        :branches

      String.contains?(path, "/branches/") and String.ends_with?(path, "/snapshot") ->
        :data_system

      String.contains?(path, "/branches/") and String.contains?(path, "/edit") ->
        :branches

      path == "/staff/branches" ->
        :branches

      path == "/staff/franchise/snapshot" ->
        :data_system

      String.starts_with?(path, "/staff/franchise") ->
        :franchise

      String.starts_with?(path, "/staff/diagnostics") or String.starts_with?(path, "/staff/logs") ->
        :data_system

      String.contains?(path, "/loyalty") ->
        nil

      true ->
        nil
    end
  end

  def active_setting(_), do: nil

  def feature_entry(key, staff) do
    {label, id} = feature_description(key)

    path =
      staff |> catalog(nil) |> Enum.find_value(fn entry -> if entry.id == id, do: entry.path end)

    path =
      if key == "yandex_costs" and can?(staff, "statistics.read") and
           can?(staff, "statistics.network"),
         do: ~p"/staff/analytics/advertising",
         else: path

    %{label: label, path: path}
  end

  defp feature_description("segments"), do: {gettext("Segments"), :segments}
  defp feature_description("couriers"), do: {gettext("Own couriers"), :delivery_settings}
  defp feature_description("notifications"), do: {gettext("Notifications"), nil}

  defp feature_description("marketing_policies"),
    do: {gettext("Marketing policies"), :marketing_policies}

  defp feature_description("analytics_funnel"), do: {gettext("Sales funnel"), :statistics}
  defp feature_description("analytics_extended"), do: {gettext("Extended analytics"), :statistics}
  defp feature_description("analytics_franchise"), do: {gettext("Network analytics"), :statistics}
  defp feature_description("analytics_links"), do: {gettext("Advertising links"), :statistics}

  defp feature_description("yandex_ads"),
    do: {gettext("Yandex Direct and Metrika"), :integrations}

  defp feature_description("yandex_browser"),
    do: {gettext("Metrika: visits and funnel"), :integrations}

  defp feature_description("yandex_conversions"),
    do: {gettext("Send completed orders as offline conversions"), :integrations}

  defp feature_description("yandex_ecommerce"),
    do: {gettext("Send product events and server purchases"), :integrations}

  defp feature_description("yandex_feed"), do: {gettext("Product feeds"), :integrations}

  defp feature_description("yandex_costs"),
    do: {gettext("Advertising costs"), :analytics_advertising}

  def integration_entry(provider, staff, branch) do
    label = integration_label(provider)

    path =
      cond do
        not can?(staff, "integrations.read") ->
          nil

        provider in [:zvonok, :dadata, :yookassa, :yandex_eda, :yandex_ads] and
            can?(staff, "admin") ->
          "/staff/integrations/#{provider_slug(provider)}"

        provider in [:zvonok, :dadata, :yookassa, :yandex_eda, :yandex_ads] ->
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
        if(provider in [:zvonok, :dadata, :yookassa, :yandex_eda, :yandex_ads],
          do: :network,
          else: :branch
        )
    }
  end

  defp provider_slug(:yandex_eda), do: "yandex-eda"
  defp provider_slug(:yandex_ads), do: "yandex-ads"
  defp provider_slug(:vk_ads), do: "vk-ads"
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
  defp integration_label(:yandex_ads), do: gettext("Yandex Direct and Metrika")
  defp integration_label(:vk_ads), do: gettext("VK Реклама / Top.Mail.Ru")
  defp integration_label(:yandex_delivery), do: gettext("Yandex Delivery")
  defp integration_label(:ycart), do: gettext("Yandex Cart")
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

    frontpad =
      if branch && can?(staff, "integrations.read") do
        [
          setting(
            :frontpad,
            gettext("Frontpad"),
            "/staff/b/#{branch.slug}/integrations/frontpad",
            "hero-puzzle-piece",
            :branch,
            ["integrations.read"],
            ["фронтпад", "отправка заказов"]
          )
        ]
      else
        []
      end

    (settings_entries(staff, branch) ++ frontpad ++ menu_items(staff, branch) ++ legacy)
    |> Enum.uniq_by(& &1.id)
  end

  def data_system_entries do
    [
      %{id: :events, path: ~p"/staff/logs", icon: "hero-clock", label: gettext("Event log")},
      %{
        id: :metrics,
        path: ~p"/staff/diagnostics",
        icon: "hero-chart-bar",
        label: gettext("Metrics")
      },
      %{
        id: :raw,
        path: ~p"/staff/logs/raw",
        icon: "hero-command-line",
        label: gettext("Raw logs")
      },
      %{
        id: :errors,
        path: ~p"/staff/logs/errors",
        icon: "hero-exclamation-triangle",
        label: gettext("Errors")
      }
    ]
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

  def network_analytics_path?(path) when is_binary(path),
    do: path == "/staff/statistics" or String.starts_with?(path, "/staff/analytics/")

  def network_analytics_path?(_), do: false

  attr :staff, :map, required: true
  attr :branch, :any, default: nil
  attr :navigation_branch, :any, default: nil
  attr :scope_branch, :any, default: nil
  attr :return_source, :string, default: nil
  attr :current_page, :any, default: nil
  attr :current_path, :string, default: nil
  attr :id_prefix, :string, default: ""
  attr :items_override, :any, default: nil
  attr :group_id, :any, default: nil

  def local_navigation(assigns) do
    navigation_branch =
      if network_analytics_path?(assigns.current_path),
        do: nil,
        else: assigns.navigation_branch || assigns.branch

    navigation_branch = navigation_branch && Delivest.Repo.preload(navigation_branch, :info)

    items =
      if is_nil(assigns.items_override) do
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
                :orders,
                :orders_new,
                :pos,
                :kitchen,
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
                :marketing,
                :employee,
                :roles,
                :statistics,
                :network_sales,
                :analytics_channels,
                :analytics_sources,
                :analytics_funnel,
                :analytics_customers,
                :analytics_comparison
              ] ->
            group.items

          true ->
            []
        end
      else
        assigns.items_override
      end

    assigns = assign(assigns, items: items)

    ~H"""
    <ul
      :if={@items != [] and @id_prefix == "sidebar-"}
      id={"#{@id_prefix}staff-section-navigation#{if @group_id, do: "-#{@group_id}"}"}
      phx-hook="ActiveSectionNav"
      aria-label={gettext("Page sections")}
    >
      <li :for={item <- @items}>
        <.local_link
          item={item}
          id_prefix={@id_prefix}
          scope_branch={@scope_branch}
          return_source={@return_source}
          current_page={@current_page}
          current_path={@current_path}
        />
      </li>
    </ul>
    <nav
      :if={@items != [] and @id_prefix == ""}
      id={"#{@id_prefix}staff-section-navigation#{if @group_id, do: "-#{@group_id}"}"}
      phx-hook="ActiveSectionNav"
      aria-label={gettext("Page sections")}
      class="flex gap-1 overflow-x-auto whitespace-nowrap border-b border-base-300 px-4 py-2 sm:px-6"
    >
      <.local_link
        :for={item <- @items}
        item={item}
        id_prefix={@id_prefix}
        scope_branch={@scope_branch}
        return_source={@return_source}
        current_page={@current_page}
        current_path={@current_path}
      />
    </nav>
    """
  end

  attr :item, :map, required: true
  attr :id_prefix, :string, required: true
  attr :scope_branch, :any, default: nil
  attr :return_source, :string, default: nil
  attr :current_page, :any, default: nil
  attr :current_path, :string, default: nil

  defp local_link(assigns) do
    ~H"""
    <.link
      id={@id_prefix <> if(@item.parent == :menu, do: "product-section-tab-#{@item.id}", else: "section-nav-#{@item.id}")}
      navigate={
        DelivestWeb.StaffBranchPath.contextual_navigation_path(
          @item.path,
          @scope_branch,
          @return_source
        )
      }
      aria-current={active_local?(@item, @current_page, @current_path) && "page"}
      class={
        if(@id_prefix == "sidebar-",
          do: active_local?(@item, @current_page, @current_path) && "menu-active",
          else: [
            "whitespace-nowrap rounded-field px-3 py-2 text-sm hover:bg-base-200",
            active_local?(@item, @current_page, @current_path) && "bg-base-200 font-semibold"
          ]
        )
      }
    >{@item.label}</.link>
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
        [] ->
          nil

        [only] when id not in [:settings, :menu, :employees, :analytics] ->
          %{only | label: label, icon: icon, pages: only.pages}

        available ->
          %{kind: :group, id: id, label: label, icon: icon, items: available}
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
          Enum.map([:deliveries, :couriers], find)
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
        top.(
          :employees,
          gettext("Employees"),
          "hero-user-group",
          Enum.map([:employee, :roles], find)
        ),
        top.(
          :analytics,
          gettext("Analytics"),
          "hero-chart-bar",
          [find.(:statistics) | analytics_entries(staff, branch)]
        )
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
    transfer_access? =
      can?(staff, "admin") or
        (can?(staff, "branches.read") and can?(staff, "branches.update") and
           has_available_branch?(staff))

    [
      setting(
        :settings,
        gettext("Settings"),
        "/staff/settings",
        "hero-cog-6-tooth",
        :network,
        [
          "franchise.update",
          "branches.read",
          "delivery.read",
          "orders.update",
          "integrations.read",
          "logs.read"
        ]
      ),
      setting(
        :data_transfer,
        gettext("Data transfer"),
        setting_path(:data_transfer, branch),
        "hero-arrow-up-tray",
        :network,
        ["branches.update", "admin"]
      ),
      setting(
        :franchise,
        gettext("Franchise"),
        "/staff/franchise",
        "hero-building-storefront",
        :network,
        ["franchise.update"],
        [gettext("brand"), gettext("logo"), "бренд"]
      ),
      setting(:branches, gettext("Branches"), "/staff/branches", "hero-map-pin", :network, [
        "branches.read",
        "delivery.read",
        "orders.update"
      ]),
      setting(
        :branch_settings,
        gettext("Branch operation"),
        branch && "/staff/branches/#{branch.slug}/edit",
        "hero-building-storefront",
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
        ["зоны", "зоны доставки"]
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
        :features,
        gettext("Capabilities"),
        setting_path(:features, branch),
        "hero-adjustments-horizontal",
        :mixed,
        ["franchise.update", "branches.read", "delivery.read", "integrations.read", "logs.read"]
      ),
      setting(
        :data_system,
        gettext("Data and system"),
        setting_path(:data_system, branch),
        "hero-beaker",
        :network,
        if(can?(staff, "logs.read"), do: ["logs.read"], else: ["branches.update", "admin"]),
        ["диагностика"]
      ),
      setting(
        :site_snapshot,
        gettext("Branch snapshot"),
        branch && "/staff/branches/#{branch.slug}/edit/snapshot",
        "hero-archive-box-arrow-down",
        :branch,
        ["branches.update"],
        ["слепок витрины"]
      ),
      setting(
        :instance_backup,
        gettext("Franchise snapshot"),
        "/staff/franchise/snapshot",
        "hero-archive-box-arrow-down",
        :network,
        ["admin"],
        ["полный слепок", "резервная копия"]
      )
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(fn
      %{id: :data_transfer} ->
        transfer_access?

      %{id: :data_system} ->
        can?(staff, "logs.read") or transfer_access?

      entry ->
        Enum.any?(entry.read_permissions, &can?(staff, &1))
    end)
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
  defp setting_path(:features, nil), do: "/staff/settings"
  defp setting_path(:features, branch), do: "/staff/settings?branch=#{branch.slug}"
  defp setting_path(:data_transfer, nil), do: "/staff/settings/data-transfer"

  defp setting_path(:data_transfer, branch),
    do: "/staff/settings/data-transfer?branch=#{branch.slug}"

  defp setting_path(:franchise, _), do: "/staff/franchise"
  defp setting_path(:branches, _), do: "/staff/branches"
  defp setting_path(:data_system, nil), do: "/staff/settings/data-system"
  defp setting_path(:data_system, branch), do: "/staff/settings/data-system?branch=#{branch.slug}"
  defp setting_path(:instance_backup, _), do: "/staff/franchise/snapshot"
  defp setting_path(:integrations, nil), do: "/staff/integrations"
  defp setting_path(:integrations, branch), do: "/staff/b/#{branch.slug}/integrations"
  defp setting_path(_id, nil), do: nil
  defp setting_path(:branch_settings, branch), do: "/staff/branches/#{branch.slug}/edit"
  defp setting_path(:delivery_settings, branch), do: "/staff/b/#{branch.slug}/delivery"
  defp setting_path(:frontpad, branch), do: "/staff/b/#{branch.slug}/integrations/frontpad"
  defp setting_path(:site_snapshot, branch), do: "/staff/branches/#{branch.slug}/edit/snapshot"

  defp has_available_branch?(staff) do
    if Ecto.assoc_loaded?(staff.branches) do
      Enum.any?(staff.branches || [], &is_nil(&1.deleted_at))
    else
      staff |> Delivest.Repo.preload(:branches) |> Identity.list_branch_for_staff() |> Enum.any?()
    end
  end

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
        |> owned(branch, :couriers)
        |> courier_available(staff, branch, :own),
        item(
          :couriers,
          branch && ~p"/staff/b/#{branch}/couriers",
          "hero-user-circle",
          gettext("Couriers")
        )
        |> allowed(staff, "orders.update")
        |> owned(branch, :couriers)
        |> courier_available(staff, branch, :dispatch)
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
      item(
        :statistics,
        if(branch, do: ~p"/staff/b/#{branch}/statistics", else: ~p"/staff/statistics"),
        "hero-chart-bar",
        gettext("Sales")
      )
      |> covering([:analytics_channels, :analytics_comparison])
      |> allowed(staff, "statistics.read")
      |> then(fn entry -> if branch || can?(staff, "statistics.network"), do: entry end),
      group(:marketing, "hero-megaphone", gettext("Marketing"), marketing_entries(staff, branch))
    ]
    |> compact_all()
  end

  defp analytics_entries(staff, branch) do
    if can?(staff, "statistics.read") and (branch || can?(staff, "statistics.network")) do
      branch_ids =
        if(branch,
          do: [branch.id],
          else: Enum.map(Identity.list_branch_for_staff(staff), & &1.id)
        )

      enabled =
        Features.enabled_branches_many(
          ~w(analytics_links analytics_funnel analytics_extended),
          branch_ids
        )

      available? = fn feature -> MapSet.size(Map.get(enabled, feature, MapSet.new())) > 0 end

      acquisition =
        cond do
          available?.("analytics_links") -> "sources"
          available?.("analytics_funnel") -> "funnel"
          is_nil(branch) and Features.enabled?("yandex_costs", :franchise) -> "advertising"
          true -> nil
        end

      acquisition_path =
        case {branch, acquisition} do
          {_, nil} -> nil
          {nil, section} -> "/staff/analytics/#{section}"
          {branch, section} -> "/staff/b/#{branch.slug}/analytics/#{section}"
        end

      buyers_path =
        if available?.("analytics_extended") do
          if branch,
            do: ~p"/staff/b/#{branch}/analytics/customers",
            else: ~p"/staff/analytics/customers"
        end

      [
        item(:analytics_acquisition, acquisition_path, "hero-megaphone", gettext("Acquisition"))
        |> covering([:analytics_sources, :analytics_funnel]),
        item(:analytics_customers, buyers_path, "hero-users", gettext("Buyers"))
      ]
    else
      []
    end
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
           do: %{item | aliases: ["бонусы"]}
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
        item(:employee, ~p"/staff/employee", "hero-user-group", gettext("Employees"))
        |> allowed(staff, "staff.read"),
        item(:roles, ~p"/staff/roles", "hero-shield-check", gettext("Roles and permissions"))
        |> allowed(staff, "roles.read")
        |> then(fn item -> item && %{item | aliases: ["права"]} end)
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
             ~w(franchise.update branches.read delivery.read integrations.read logs.read),
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

  defp courier_available(nil, _staff, _branch, _kind), do: nil
  defp courier_available(item, _staff, nil, _kind), do: item

  defp courier_available(item, staff, branch, kind) do
    available? =
      Couriers.own_enabled?(branch.id) or can?(staff, "admin") or
        case kind do
          :own ->
            Couriers.active_for_staff?(staff, branch.id) or
              Couriers.unsettled_for_staff?(staff, branch.id)

          :dispatch ->
            Couriers.active_any_in_branch?(branch.id) or
              Couriers.unsettled_any_in_branch?(branch.id)
        end

    if available?, do: item
  end

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
