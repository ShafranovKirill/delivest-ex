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

  def create_order(attrs) do
    Multi.new()
    |> Multi.run(:client, fn _repo, _ ->
      get_or_create_client(attrs)
    end)
    |> Multi.run(:cart, fn _repo, _ ->
      fetch_cart(attrs)
    end)
    |> Multi.run(:products, fn _repo, %{cart: cart} ->
      fetch_products_for_cart(cart)
    end)
    |> Multi.run(:order_number, fn _repo, _ ->
      OrderNumber.generate()
    end)
    |> Multi.insert(:order, fn %{
                                 client: client,
                                 cart: cart,
                                 products: products,
                                 order_number: number
                               } ->
      build_order_changeset(number, client, cart, products, attrs)
    end)
    |> Multi.run(:clear_cart, fn _repo, %{cart: cart} ->
      clear_cart_in_transaction(cart.id)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{order: order}} ->
        {:ok, Repo.preload(order, :items)}

      {:error, step, reason, _changes} ->
        {:error, step, reason}
    end
  end

  def update_order(%Order{} = order, attrs) do
    order = Repo.preload(order, :items)

    Multi.new()
    |> Multi.run(:client, fn _repo, _ ->
      maybe_resolve_client(order, attrs)
    end)
    |> Multi.run(:prepared_attrs, fn _repo, %{client: client} ->
      prepare_update_attrs(order, client, attrs)
    end)
    |> Multi.update(:order, fn %{prepared_attrs: prepared_attrs} ->
      Order.changeset(order, prepared_attrs)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{order: updated_order}} ->
        {:ok, Repo.preload(updated_order, :items, force: true)}

      {:error, step, reason, _changes} ->
        {:error, step, reason}
    end
  end

  def soft_delete_order(%Order{} = order) do
    order
    |> Order.changeset(%{deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    |> Repo.update()
  end

  defp maybe_resolve_client(_order, %{"phone" => phone} = attrs) when not is_nil(phone) do
    client_attrs = %{name: Map.get(attrs, "client_name")}
    {:ok, Identity.get_or_create_client_by_phone(phone, client_attrs)}
  end

  defp maybe_resolve_client(_order, _attrs), do: {:ok, nil}

  defp prepare_update_attrs(_order, client, attrs) do
    client_id = extract_client_id(client)

    attrs =
      if client_id do
        Map.put(attrs, "client_id", client_id)
      else
        attrs
      end

    case Map.get(attrs, "items") do
      nil ->
        {:ok, attrs}

      new_items_params ->
        recalculate_items_and_total(new_items_params, attrs)
    end
  end

  defp recalculate_items_and_total(items_params, attrs) do
    product_ids =
      Enum.map(items_params, fn item ->
        item["product_id"] || item[:product_id]
      end)

    # Net.list_products_by_ids возвращает Map вида %{id => %Product{}}
    products_map = Net.list_products_by_ids(product_ids, [])

    {items_attrs, total_amount} =
      Enum.reduce(items_params, {[], 0}, fn item_param, {acc_items, acc_total} ->
        product_id = item_param["product_id"] || item_param[:product_id]
        quantity = parse_quantity(item_param["quantity"] || item_param[:quantity])

        case Map.get(products_map, product_id) do
          nil ->
            {acc_items, acc_total}

          product ->
            price = product.price
            item_total = price * quantity

            item_data = %{
              product_id: product_id,
              title: product.name,
              price: price,
              quantity: quantity
            }

            {[item_data | acc_items], acc_total + item_total}
        end
      end)

    updated_attrs =
      attrs
      |> Map.put("items", items_attrs)
      |> Map.put("total_amount", total_amount)

    {:ok, updated_attrs}
  end

  defp parse_quantity(q) when is_integer(q), do: q
  defp parse_quantity(q) when is_binary(q), do: String.to_integer(q)
  defp parse_quantity(_), do: 1

  defp get_or_create_client(%{"phone" => phone} = attrs) when not is_nil(phone) and phone != "" do
    client_attrs = %{name: Map.get(attrs, "client_name")}
    {:ok, Identity.get_or_create_client_by_phone(phone, client_attrs)}
  end

  defp get_or_create_client(_), do: {:ok, nil}

  defp fetch_cart(attrs) when is_map(attrs) do
    cart_id = Map.get(attrs, "cart_id") || Map.get(attrs, :cart_id)
    fetch_cart(cart_id)
  end

  defp fetch_cart(cart_id) when is_binary(cart_id) or is_integer(cart_id) do
    case Carts.get_cart_by_id(cart_id) do
      nil ->
        {:error, :cart_not_found}

      %CartView{items: []} ->
        {:error, :cart_is_empty}

      %CartView{} = cart ->
        {:ok, cart}
    end
  end

  defp fetch_cart(_), do: {:error, :cart_not_found}

  defp fetch_products_for_cart(%{items: items}) do
    product_ids = Enum.map(items, & &1.product_id)
    products_map = Net.list_products_by_ids(product_ids, [])

    {:ok, products_map}
  end

  defp build_order_changeset(number, client, cart, products_map, attrs) do
    {items_attrs, total_amount} =
      Enum.reduce(cart.items, {[], 0}, fn item, {acc_items, acc_total} ->
        case Map.get(products_map, item.product_id) do
          nil ->
            {acc_items, acc_total}

          product ->
            price = product.price
            item_total = price * item.quantity

            order_item = %{
              product_id: item.product_id,
              title: product.name,
              price: price,
              quantity: item.quantity
            }

            {[order_item | acc_items], acc_total + item_total}
        end
      end)

    client_id = extract_client_id(client)

    order_params =
      attrs
      |> Map.put("number", number)
      |> Map.put("total_amount", total_amount)
      |> Map.put("branch_id", cart.branch_id)
      |> Map.put("staff_id", cart.staff_id)
      |> Map.put("client_id", client_id)

    %Order{}
    |> Order.changeset(order_params)
    |> Ecto.Changeset.put_assoc(:items, items_attrs)
  end

  defp extract_client_id({:ok, %{id: id}}), do: id
  defp extract_client_id(%{id: id}), do: id
  defp extract_client_id(_), do: nil

  defp clear_cart_in_transaction(cart_id) do
    case Repo.get(Delivest.Oms.Cart, cart_id) do
      %Delivest.Oms.Cart{} = cart ->
        Repo.delete(cart)
        Cachex.del(@cache_store, cart.id)
        {:ok, :deleted}

      nil ->
        Cachex.del(@cache_store, cart_id)
        {:ok, :not_found}
    end
  end
end
