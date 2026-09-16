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
    |> Multi.run(:order_number, fn _, _ -> OrderNumber.generate() end)
    |> Multi.insert(:order, fn %{
                                 client_id: client_id,
                                 cart: cart,
                                 products: products,
                                 order_number: num
                               } ->
      build_order_from_cart(%Order{}, num, client_id, cart, products, attrs)
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
    |> Multi.run(:client_id, fn _, _ -> resolve_client_id_on_update(order, attrs) end)
    |> Multi.run(:cart, fn _, _ -> fetch_cart(attrs) end)
    |> Multi.run(:products, fn _, %{cart: cart} -> fetch_products_for_cart(cart) end)
    |> Multi.update(:order, fn %{client_id: client_id, cart: cart, products: products} ->
      build_order_from_cart(order, order.number, client_id, cart, products, attrs)
    end)
    |> Multi.run(:clear_cart, fn _, %{cart: cart} -> clear_cart_in_transaction(cart.id) end)
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
    phone = Map.get(attrs, "customer_phone")

    if is_nil(phone) || String.trim(phone) == "" do
      {:ok, nil}
    else
      Identity.resolve_client(attrs)
    end
  end

  defp resolve_client_id_on_update(order, attrs) do
    phone = Map.get(attrs, "customer_phone")

    if is_nil(phone) || String.trim(phone) == "" do
      {:ok, nil}
    else
      case Identity.resolve_client(attrs) do
        {:ok, nil} -> {:ok, order.client_id}
        {:ok, new_client_id} -> {:ok, new_client_id}
        {:error, reason} -> {:error, reason}
      end
    end
  end

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

  defp build_order_from_cart(order_struct, number, client_id, cart, products_map, attrs) do
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
      |> Map.put("number", to_string(number))
      |> Map.put("total_amount", total_amount)
      |> Map.put("branch_id", cart.branch_id)
      |> Map.put("cart_id", cart.id)
      |> Map.put_new("staff_id", cart.staff_id)
      |> Map.put("client_id", client_id)

    order_struct
    |> Order.changeset(order_params)
    |> Ecto.Changeset.put_assoc(:items, items_attrs)
  end

  defp clear_cart_in_transaction(cart_id) do
    case Repo.get(Delivest.Oms.Cart, cart_id) do
      %Delivest.Oms.Cart{} = cart -> Repo.delete(cart)
      nil -> :ok
    end

    Cachex.del(@cache_store, cart_id)
    {:ok, :deleted}
  end
end
