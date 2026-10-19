defmodule Delivest.Oms.Orders do
  import Ecto.Query, warn: false

  alias Delivest.Identity
  alias Delivest.Net
  alias Delivest.Oms.{Cart, CartView, Carts, Order}
  alias Delivest.Oms.Order.OrderNumber
  alias Delivest.Oms.Orders.Filter
  alias Delivest.Repo
  alias Ecto.Multi

  @topic inspect(__MODULE__)

  def subscribe do
    Phoenix.PubSub.subscribe(Delivest.PubSub, @topic)
  end

  def list_orders(params \\ %{}) do
    Order
    |> where([o], is_nil(o.deleted_at))
    |> Filter.apply_filters(Filter.normalize_params(params))
    |> preload([:items, :client])
    |> Repo.all()
  end

  def list_client_orders(client_id, branch_scope, limit \\ 50) do
    Order
    |> where([o], o.client_id == ^client_id and is_nil(o.deleted_at))
    |> then(fn query ->
      case branch_scope do
        :all -> query
        ids -> where(query, [o], o.branch_id in ^ids)
      end
    end)
    |> order_by([o], desc: o.inserted_at)
    |> limit(^limit)
    |> preload(:items)
    |> Repo.all()
  end

  def get_order(id) do
    Order
    |> Repo.get(id)
    |> Repo.preload([:client, :items])
  end

  def create_order(attrs, opts \\ []) do
    attrs = Filter.normalize_params(attrs)
    after_insert = Keyword.get(opts, :after_insert, & &1)

    Multi.new()
    |> Multi.run(:client_id, fn _, _ ->
      resolve_client_id_on_create(attrs, update_existing: Keyword.get(opts, :update_client, true))
    end)
    |> Multi.run(:cart, fn _, _ -> fetch_cart_for_new_order(attrs) end)
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
    |> after_insert.()
    |> Multi.run(:detached_cart, fn _, %{cart: cart} ->
      Carts.detach_cart(cart)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{order: order}} ->
        order = Repo.preload(order, [:items, :client])
        notify_subscribers({:ok, order}, [:order, :created])

      {:error, step, reason, _} ->
        {:error, step, reason}
    end
  end

  def update_order(%Order{} = order, attrs) do
    attrs = Filter.normalize_params(attrs)

    Multi.new()
    |> Multi.run(:client_id, fn _, _ -> resolve_client_id_on_update(order, attrs) end)
    |> Multi.run(:cart, fn _, _ -> fetch_cart(attrs) end)
    |> Multi.run(:products, fn _, %{cart: cart} -> fetch_products_for_cart(cart) end)
    |> Multi.update(:order, fn %{client_id: client_id, cart: cart, products: products} ->
      build_order_from_cart(order, order.number, client_id, cart, products, attrs)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{order: updated_order}} ->
        updated_order = Repo.preload(updated_order, [:items, :client], force: true)
        notify_subscribers({:ok, updated_order}, [:order, :updated])

      {:error, step, reason, _} ->
        {:error, step, reason}
    end
  end

  def update_order_details(%Order{} = order, attrs) do
    attrs = attrs |> Filter.normalize_params() |> Map.take(["status", "payment_method"])

    order
    |> Order.details_changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated_order} ->
        updated_order = Repo.preload(updated_order, [:items, :client], force: true)
        notify_subscribers({:ok, updated_order}, [:order, :updated])

      error ->
        error
    end
  end

  def soft_delete_order(%Order{} = order) do
    result =
      order
      |> Order.changeset(%{deleted_at: DateTime.truncate(DateTime.utc_now(), :second)})
      |> Repo.update()

    notify_subscribers(result, [:order, :deleted])
  end

  def populate_cart_from_order(%Order{} = order, cart_id) do
    Carts.clear_cart(cart_id)

    Enum.each(order.items, fn item ->
      Carts.add_item(cart_id, item.product_id, item.quantity)
    end)

    Carts.get_cart_by_id(cart_id)
  end

  def update_order_crm_info(%Order{} = order, attrs) do
    result =
      order
      |> Order.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, updated_order} ->
        updated_order = Repo.preload(updated_order, [:items, :client], force: true)
        notify_subscribers({:ok, updated_order}, [:order, :updated])

      error ->
        error
    end
  end

  defp resolve_client_id_on_create(attrs, client_opts) do
    phone = Map.get(attrs, "customer_phone")

    if is_nil(phone) || String.trim(phone) == "" do
      {:ok, nil}
    else
      Identity.resolve_client(attrs, client_opts)
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

  defp fetch_cart_for_new_order(attrs) do
    with {:ok, cart_id} <- cast_cart_id(Map.get(attrs, "cart_id")),
         :ok <- lock_cart(cart_id),
         :ok <- ensure_cart_not_ordered(cart_id),
         {:ok, cart} <- fetch_cart(attrs),
         :ok <- ensure_cart_branch(cart, Map.get(attrs, "branch_id")) do
      {:ok, cart}
    end
  end

  defp cast_cart_id(cart_id) do
    case Ecto.UUID.cast(cart_id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :cart_not_found}
    end
  end

  defp lock_cart(cart_id) do
    query = from(c in Cart, where: c.id == ^cart_id, lock: "FOR UPDATE", select: c.id)

    case Repo.one(query) do
      nil -> {:error, :cart_not_found}
      _id -> :ok
    end
  end

  defp ensure_cart_not_ordered(cart_id) do
    if Repo.exists?(from(o in Order, where: o.cart_id == ^cart_id)) do
      {:error, :cart_already_ordered}
    else
      :ok
    end
  end

  defp ensure_cart_branch(_cart, nil), do: :ok

  defp ensure_cart_branch(%CartView{branch_id: branch_id}, branch_id), do: :ok

  defp ensure_cart_branch(_cart, _branch_id), do: {:error, :cart_branch_mismatch}

  defp fetch_products_for_cart(%{items: items}) do
    product_ids =
      Enum.map(items, fn item ->
        item[:product_id] || Map.get(item, "product_id")
      end)

    {:ok, Net.list_products_by_ids(product_ids, preload: [:category])}
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
            item = %{
              product_id: pid,
              title: p.name,
              price: p.price,
              quantity: qty,
              category_id: p.category_id,
              category_name: category_name(p)
            }

            {[item | acc_items], acc_total + p.price * qty}
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

  defp category_name(%{category: %{name: name}}), do: name
  defp category_name(_product), do: nil

  defp notify_subscribers({:ok, order}, event) do
    Phoenix.PubSub.broadcast(Delivest.PubSub, @topic, {__MODULE__, event, order})
    {:ok, order}
  end

  defp notify_subscribers({:error, step, reason}, _event) do
    {:error, step, reason}
  end

  defp notify_subscribers({:error, reason}, _event) do
    {:error, reason}
  end
end
