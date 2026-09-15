defmodule Delivest.Oms.Orders do
  import Ecto.Query, warn: false

  alias Delivest.Identity
  alias Delivest.Net
  alias Delivest.Oms.CartView
  alias Delivest.Oms.Carts
  alias Delivest.Oms.Order
  alias Delivest.Oms.Order.OrderNumber
  alias Delivest.Repo
  alias Ecto.Multi

  @cache_store :cart_cache
  @confirmed_statuses ~w(preparing ready delivering completed)s ++
                        [:preparing, :ready, :delivering, :completed]

  def list_orders(params \\ %{}) do
    Order
    |> where([o], is_nil(o.deleted_at))
    |> apply_filters(normalize_params(params))
    |> preload([:items, :client])
    |> Repo.all()
  end

  def get_order!(id) do
    Order
    |> Repo.get!(id)
    |> Repo.preload([:client, :items])
  end

  def create_order(attrs) do
    attrs = normalize_params(attrs)

    Multi.new()
    |> Multi.run(:client_id, fn _, _ -> resolve_client_id_on_create(attrs) end)
    |> Multi.run(:cart, fn _, _ -> fetch_cart(attrs) end)
    |> Multi.run(:products, fn _, %{cart: cart} -> fetch_products_for_cart(cart) end)
    |> Multi.run(:order_number, fn _, _ -> {:ok, OrderNumber.generate()} end)
    |> Multi.insert(:order, fn %{client_id: client_id, cart: cart, products: p, order_number: num} ->
      build_order_changeset(num, client_id, cart, p, attrs)
    end)
    |> Multi.run(:clear_cart, fn _, %{cart: cart} -> clear_cart_in_transaction(cart.id) end)
    |> Repo.transaction()
    |> case do
      {:ok, %{order: order}} -> {:ok, Repo.preload(order, [:items, :client])}
      {:error, step, reason, _} -> {:error, step, reason}
    end
  end

  def update_order(%Order{} = order, attrs) do
    attrs = normalize_params(attrs)

    Multi.new()
    |> Multi.run(:client, fn _, _ -> resolve_client_on_update(order, attrs) end)
    |> Multi.run(:prepared_attrs, fn _, %{client: client} ->
      prepare_update_attrs(order, client, attrs)
    end)
    |> Multi.update(:order, fn %{prepared_attrs: prepared_attrs} ->
      Order.changeset(order, prepared_attrs)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{order: updated_order}} ->
        {:ok, Repo.preload(updated_order, [:items, :client], force: true)}

      {:error, step, reason, _} ->
        {:error, step, reason}
    end
  end

  def soft_delete_order(%Order{} = order) do
    order
    |> Order.changeset(%{deleted_at: DateTime.truncate(DateTime.utc_now(), :second)})
    |> Repo.update()
  end

  def populate_cart_from_order(%Order{} = order, cart_id) do
    Carts.clear_cart(cart_id)

    Enum.each(order.items, fn item ->
      Carts.add_item(cart_id, item.product_id, item.quantity)
    end)

    Carts.get_cart_by_id(cart_id)
  end

  # Helpers

  defp normalize_params(params) when is_map(params) do
    Map.new(params, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {to_string(k), v}
    end)
  end

  defp apply_filters(query, params) do
    Enum.reduce(params, query, fn
      {_key, val}, q when val in [nil, ""] -> q
      {"branch_id", val}, q -> where(q, [o], o.branch_id == ^val)
      {"status", val}, q -> where(q, [o], o.status == ^val)
      {"date_from", val}, q -> filter_date_from(q, val)
      {"date_to", val}, q -> filter_date_to(q, val)
      {"sort_by", val}, q -> apply_sort(q, val, params["sort_dir"])
      _, q -> q
    end)
  end

  defp filter_date_from(q, %Date{} = date) do
    where(q, [o], o.inserted_at >= ^DateTime.new!(date, ~T[00:00:00], "Etc/UTC"))
  end

  defp filter_date_from(q, str) when is_binary(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> filter_date_from(q, d)
      _ -> q
    end
  end

  defp filter_date_to(q, %Date{} = date) do
    where(q, [o], o.inserted_at <= ^DateTime.new!(date, ~T[23:59:59], "Etc/UTC"))
  end

  defp filter_date_to(q, str) when is_binary(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> filter_date_to(q, d)
      _ -> q
    end
  end

  defp apply_sort(q, field, dir) do
    sort_field =
      case field do
        f when f in ["total_amount", "status"] -> String.to_existing_atom(f)
        _ -> :inserted_at
      end

    sort_dir = if dir in ["asc", :asc], do: :asc, else: :desc
    order_by(q, [o], [{^sort_dir, ^sort_field}])
  end

  defp resolve_client_id_on_create(attrs) do
    case Map.get(attrs, "client_id") do
      client_id when is_binary(client_id) and client_id != "" -> {:ok, client_id}
      _ -> {:ok, nil}
    end
  end

  defp resolve_client_on_update(order, attrs) do
    new_status = Map.get(attrs, "status", order.status)

    incoming_phone =
      Map.get(attrs, "customer_phone") || Map.get(attrs, "phone")

    incoming_client_id = Map.get(attrs, "client_id")
    new_name = name_for_order(order, attrs)

    client_id_changed? = present?(incoming_client_id) and incoming_client_id != order.client_id

    current_phone = order.customer_phone || (order.client && order.client.phone)
    phone_changed? = present?(incoming_phone) and incoming_phone != current_phone

    target_phone = incoming_phone || current_phone
    becoming_confirmed? = new_status in @confirmed_statuses

    cond do
      phone_changed? ->
        if becoming_confirmed? do
          Identity.get_or_create_client_by_phone(incoming_phone, %{name: new_name})
        else
          {:ok, nil}
        end

      client_id_changed? ->
        {:ok, %{id: incoming_client_id}}

      becoming_confirmed? and is_nil(order.client_id) and present?(target_phone) ->
        Identity.get_or_create_client_by_phone(target_phone, %{name: new_name})

      not is_nil(order.client_id) ->
        {:ok, order.client}

      true ->
        {:ok, nil}
    end
  end

  defp prepare_update_attrs(_order, client, attrs) do
    client_id = extract_client_id(client)
    attrs = Map.put(attrs, "client_id", client_id)

    case Map.get(attrs, "items") do
      nil -> {:ok, attrs}
      items -> recalculate_items_and_total(items, attrs)
    end
  end

  defp recalculate_items_and_total(items_params, attrs) do
    items_params = Enum.map(items_params, &normalize_params/1)
    product_ids = Enum.map(items_params, & &1["product_id"])
    products_map = Net.list_products_by_ids(product_ids, [])

    {items_attrs, total_amount} =
      Enum.reduce(items_params, {[], 0}, fn item_param, {acc_items, acc_total} ->
        pid = item_param["product_id"]
        qty = parse_quantity(item_param["quantity"])

        case Map.get(products_map, pid) do
          nil ->
            {acc_items, acc_total}

          p ->
            {[%{product_id: pid, title: p.name, price: p.price, quantity: qty} | acc_items],
             acc_total + p.price * qty}
        end
      end)

    {:ok, attrs |> Map.put("items", items_attrs) |> Map.put("total_amount", total_amount)}
  end

  defp parse_quantity(q) when is_integer(q), do: q

  defp parse_quantity(q) when is_binary(q) do
    case Integer.parse(q) do
      {int, _} -> int
      :error -> 1
    end
  end

  defp parse_quantity(_), do: 1

  defp fetch_cart(attrs) do
    case Map.get(attrs, "cart_id") do
      nil ->
        {:error, :cart_not_found}

      cart_id ->
        case Carts.get_cart_by_id(cart_id) do
          nil -> {:error, :cart_not_found}
          %CartView{items: []} -> {:error, :cart_is_empty}
          %CartView{} = cart -> {:ok, cart}
        end
    end
  end

  defp fetch_products_for_cart(%{items: items}) do
    product_ids =
      Enum.map(items, fn item ->
        item[:product_id] || Map.get(item, "product_id")
      end)

    {:ok, Net.list_products_by_ids(product_ids, [])}
  end

  defp build_order_changeset(number, client_id, cart, products_map, attrs) do
    {items_attrs, total_amount} =
      Enum.reduce(cart.items, {[], 0}, fn item, {acc_items, acc_total} ->
        pid = item[:product_id] || Map.get(item, "product_id")
        qty = item[:quantity] || Map.get(item, "quantity")

        case Map.get(products_map, pid) do
          nil ->
            {acc_items, acc_total}

          p ->
            {[%{product_id: pid, title: p.name, price: p.price, quantity: qty} | acc_items],
             acc_total + p.price * qty}
        end
      end)

    order_params =
      attrs
      |> Map.put("number", number)
      |> Map.put("total_amount", total_amount)
      |> Map.put("branch_id", cart.branch_id)
      |> Map.put("staff_id", cart.staff_id)
      |> Map.put("client_id", client_id)
      |> Map.put_new("customer_phone", Map.get(attrs, "phone"))
      |> Map.put_new("customer_name", Map.get(attrs, "client_name"))

    %Order{}
    |> Order.changeset(order_params)
    |> Ecto.Changeset.put_assoc(:items, items_attrs)
  end

  defp extract_client_id({:ok, %{id: id}}), do: id
  defp extract_client_id(%{id: id}), do: id
  defp extract_client_id(_), do: nil

  defp name_for_order(order, attrs) do
    Map.get(attrs, "customer_name") ||
      Map.get(attrs, "client_name") ||
      order.customer_name
  end

  defp present?(str) when is_binary(str), do: String.trim(str) != ""
  defp present?(_), do: false

  defp clear_cart_in_transaction(cart_id) do
    case Repo.get(Delivest.Oms.Cart, cart_id) do
      %Delivest.Oms.Cart{} = cart -> Repo.delete(cart)
      nil -> :ok
    end

    Cachex.del(@cache_store, cart_id)
    {:ok, :deleted}
  end
end
