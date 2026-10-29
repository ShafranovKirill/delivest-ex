defmodule DelivestWeb.CommandSearch do
  use DelivestWeb, :verified_routes
  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.Oms.Order

  import Delivest.Identity.Acl

  alias Delivest.{Identity, Net}
  alias Delivest.Oms.Orders

  @limit 5
  @min_length 2

  def run(staff, branch, query) do
    query = String.trim(query)

    [
      group(:pages, gettext("Pages"), pages(staff, branch, query)),
      group(:orders, gettext("Orders"), orders(staff, branch, query)),
      group(:clients, gettext("Clients"), clients(staff, query)),
      group(:products, gettext("Products"), products(staff, branch, query))
    ]
    |> Enum.reject(&(&1.items == []))
  end

  defp group(id, label, items), do: %{id: id, label: label, items: items}

  defp pages(staff, branch, query) do
    staff
    |> DelivestWeb.StaffNav.pages(branch)
    |> Enum.filter(&matches?(&1.label, query))
    |> Enum.map(&item("page-#{&1.page}", &1.label, nil, &1.icon, &1.path))
  end

  defp orders(staff, branch, query) do
    if (searchable?(query) and branch) && can?(staff, "orders.read") do
      %{branch_id: branch.id, search: query}
      |> Orders.list_latest_orders(@limit)
      |> Enum.map(&order_item(&1, branch))
    else
      []
    end
  end

  defp order_item(order, branch),
    do:
      item(
        "order-#{order.id}",
        gettext("Order #%{number}", number: Order.short_number(order)),
        order.client && join([order.client.name, order.client.phone]),
        "hero-shopping-bag",
        ~p"/staff/b/#{branch}/orders/#{order.id}"
      )

  defp clients(staff, query) do
    with true <- searchable?(query) and can?(staff, "clients.read"),
         clients when is_list(clients) <- Identity.search_clients(staff, query, @limit) do
      Enum.map(clients, &client_item/1)
    else
      _ -> []
    end
  end

  defp client_item(client),
    do:
      item(
        "client-#{client.id}",
        client.name || client.phone,
        client.name && client.phone,
        "hero-user",
        ~p"/staff/clients/#{client.id}"
      )

  defp products(staff, branch, query) do
    params = %{
      filters: [%{field: :name, op: :ilike_and, value: query}],
      page_size: @limit
    }

    with true <- (searchable?(query) and branch) && can?(staff, "products.read"),
         {:ok, {products, _meta}} <- Net.list_staff_products_for_branch(staff, branch.id, params) do
      Enum.map(products, &product_item(&1, staff, branch))
    else
      _ -> []
    end
  end

  defp product_item(product, staff, branch),
    do:
      item(
        "product-#{product.id}",
        product.name,
        to_string(product.price),
        "hero-cube",
        product_path(product, staff, branch)
      )

  defp product_path(product, staff, branch) do
    if can?(staff, "products.update"),
      do: ~p"/staff/b/#{branch}/products/#{product.id}/edit",
      else: ~p"/staff/b/#{branch}/products?#{%{search: product.name}}"
  end

  defp item(id, label, hint, icon, path),
    do: %{id: id, label: label, hint: hint, icon: icon, path: path}

  defp searchable?(query), do: String.length(query) >= @min_length

  defp matches?(_label, ""), do: true

  defp matches?(label, query),
    do: String.contains?(String.downcase(label), String.downcase(query))

  defp join(parts), do: parts |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(" · ")
end
