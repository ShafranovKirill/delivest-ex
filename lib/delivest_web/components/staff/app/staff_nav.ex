defmodule DelivestWeb.StaffNav do
  use DelivestWeb, :html

  import Delivest.Identity.Acl

  alias Delivest.Gateway

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
      section(:network, gettext("Network"), network_entries(staff))
    ]
    |> Enum.reject(&(&1.entries == []))
  end

  defp branch_entries(staff, branch) do
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
        |> owned(branch, :kitchen),
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
          :stops,
          branch && ~p"/staff/b/#{branch}/products/stops",
          "hero-no-symbol",
          gettext("Stop list")
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
        |> allowed(staff, "promotions.read"),
        item(
          :loyalty,
          branch && ~p"/staff/b/#{branch}/loyalty",
          "hero-star",
          gettext("Loyalty")
        )
        |> allowed(staff, "promotions.read")
        |> owned(branch, :loyalty)
      ]),
      item(
        :delivery,
        branch && ~p"/staff/b/#{branch}/delivery",
        "hero-truck",
        gettext("Delivery")
      )
      |> allowed(staff, "delivery.read"),
      item(
        :integrations,
        branch && ~p"/staff/b/#{branch}/integrations",
        "hero-puzzle-piece",
        gettext("Integrations")
      )
      |> allowed(staff, "integrations.read")
    ]
    |> compact_all()
  end

  defp network_entries(staff) do
    [
      item(:branches, ~p"/staff/branches", "hero-map-pin", gettext("Branches"))
      |> allowed(staff, "branches.read"),
      item(:clients, ~p"/staff/clients", "hero-users", gettext("Clients"))
      |> allowed(staff, "clients.read"),
      group(:people, "hero-user-group", gettext("Team"), [
        item(:employee, ~p"/staff/employee", "hero-user-group", gettext("Staff"))
        |> allowed(staff, "staff.read"),
        item(:roles, ~p"/staff/roles", "hero-shield-check", gettext("Roles"))
        |> allowed(staff, "roles.read")
      ]),
      item(
        :franchise,
        ~p"/staff/franchise",
        "hero-building-storefront",
        gettext("Franchise settings")
      )
      |> allowed(staff, "franchise.update"),
      item(:logs, ~p"/staff/logs", "hero-document-magnifying-glass", gettext("Logs"))
      |> allowed(staff, "logs.read")
    ]
    |> compact_all()
  end

  defp compact_all(entries), do: entries |> Enum.map(&compact/1) |> Enum.reject(&is_nil/1)

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

  defp allowed(item, staff, permission), do: if(can?(staff, permission), do: item)
end
