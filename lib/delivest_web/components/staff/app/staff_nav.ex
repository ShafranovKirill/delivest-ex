defmodule DelivestWeb.StaffNav do
  use DelivestWeb, :html

  import Delivest.Identity.Acl

  alias Delivest.{Features, Gateway, Identity, Segments}

  def pages(staff, branch) do
    staff
    |> entries(branch)
    |> Enum.flat_map(& &1.entries)
    |> Enum.flat_map(fn
      %{kind: :group, items: items} -> items
      item -> [item]
    end)
  end

  def entries(staff, branch) do
    [
      section(:branch, branch && branch.name, branch_entries(staff, branch)),
      section(
        :network,
        gettext("Network"),
        common_entries(staff, branch) ++ network_entries(staff)
      )
    ]
    |> Enum.reject(&(&1.entries == []))
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
          branch && ~p"/staff/b/#{branch}/finance/payments",
          "hero-credit-card",
          gettext("Payment")
        )
        |> allowed(staff, "finance.read"),
        item(
          :receipts,
          branch && ~p"/staff/b/#{branch}/finance/receipts",
          "hero-document-text",
          gettext("Receipts")
        )
        |> allowed(staff, "orders.update")
        |> owned(branch, :receipts)
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
        |> covering([:tags, :suggested])
        |> allowed(staff, "products.read"),
        item(
          :popular,
          branch && ~p"/staff/b/#{branch}/menu/popular",
          "hero-fire",
          gettext("Popular products")
        )
        |> allowed(staff, "products.read"),
        item(
          :stops,
          branch && ~p"/staff/b/#{branch}/products/stops",
          "hero-no-symbol",
          gettext("Stop list")
        )
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
        ~p"/staff/marketing/policies",
        "hero-rectangle-stack",
        gettext("Marketing policies")
      )
      |> then(fn item ->
        if can?(staff, "marketing.read") and Features.enabled?("marketing_policies", :franchise),
          do: item
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
      item(:loyalty, ~p"/staff/marketing/bonuses", "hero-star", gettext("Bonuses"))
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
      |> available_in(available_branches, &Features.enabled?("analytics_links", {:branch, &1.id}))
    ]
    |> Enum.reject(&is_nil/1)
  end

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
        item(:segments, ~p"/staff/segments", "hero-user-group", "Сегменты")
        |> allowed(staff, "segments.read")
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
    do: %{kind: :item, page: page, pages: [page], path: path, icon: icon, label: label}

  defp covering(nil, _pages), do: nil
  defp covering(item, pages), do: %{item | pages: [item.page | pages]}

  defp section(id, label, entries), do: %{id: id, label: label, entries: entries}

  defp group(id, icon, label, items),
    do: %{kind: :group, id: id, icon: icon, label: label, items: items}

  defp owned(nil, _branch, _area), do: nil
  defp owned(item, nil, _area), do: item
  defp owned(item, branch, area), do: if(Gateway.own?(branch, area), do: item)

  defp operating(nil, _branch), do: nil
  defp operating(item, nil), do: item
  defp operating(item, branch), do: if(Delivest.Oms.Kitchen.working?(branch), do: item)

  defp allowed(item, staff, permission), do: if(can?(staff, permission), do: item)
end
