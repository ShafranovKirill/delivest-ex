defmodule Delivest.Oms.Carts do
  import Ecto.Query, warn: false

  alias Delivest.{Repo, Net}
  alias Delivest.Net.Modifiers
  alias Delivest.Oms.{Cart, CartItem, CartPricing, CartView}

  @cache_store :cart_cache
  @cache_ttl :timer.hours(2)

  def get_or_create_cart(opts) when is_list(opts) do
    case get_cart(opts) do
      %CartView{} = cart_view ->
        {:ok, cart_view}

      nil ->
        create_cart(opts)
    end
  end

  def get_cart(opts) when is_list(opts) do
    case fetch_raw_cart(opts) do
      %Cart{id: cart_id} -> get_cart_by_id(cart_id, opts)
      nil -> nil
    end
  end

  def get_cart_by_id(cart_id, opts \\ []) when is_integer(cart_id) or is_binary(cart_id) do
    force? = Keyword.get(opts, :force, false)
    fetch_cached_or_recalculate(cart_id, force?)
  end

  def create_cart(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)

    %Cart{}
    |> Cart.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, %Cart{} = cart} ->
        cart_view = recalculate_and_cache(cart)
        {:ok, cart_view}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def clear_cart(cart_id) do
    Repo.transaction(fn ->
      {_count, _} = Repo.delete_all(from ci in CartItem, where: ci.cart_id == ^cart_id)

      refresh_and_cache(cart_id)
    end)
  end

  def owned_by_session?(_cart_id, nil), do: false

  def owned_by_session?(cart_id, session_id) do
    case Ecto.UUID.cast(cart_id) do
      {:ok, uuid} ->
        Repo.exists?(from(c in Cart, where: c.id == ^uuid and c.session_id == ^session_id))

      :error ->
        false
    end
  end

  def add_item(cart_id, product_id, quantity \\ 1, modifiers \\ nil)
      when is_integer(quantity) and quantity > 0 do
    with %Cart{} = cart <- Repo.get(Cart, cart_id) || {:error, :cart_not_found},
         {:ok, product_uuid} <- available_product(product_id, cart.branch_id),
         {:ok, choices} <- choose(product_uuid, cart.branch_id, modifiers),
         {:ok, item} <- upsert_item(cart.id, product_uuid, quantity, choices) do
      {:ok, item, recalculate_and_cache(cart)}
    end
  end

  def replace_item(cart_id, key, modifiers) do
    {product_part, modifier_key} = parse_item_key(key)

    with %Cart{} = cart <- Repo.get(Cart, cart_id) || {:error, :cart_not_found},
         {:ok, product_uuid} <- available_product(product_part, cart.branch_id),
         {:ok, choices} <- choose(product_uuid, cart.branch_id, modifiers),
         %CartItem{} = old <-
           Repo.get_by(CartItem,
             cart_id: cart.id,
             product_id: product_uuid,
             modifier_key: modifier_key
           ) || {:error, :item_not_found},
         {:ok, _item} <- swap_choices(old, choices) do
      {:ok, recalculate_and_cache(cart)}
    end
  end

  defp swap_choices(%CartItem{} = old, choices) do
    new_key = Modifiers.key(choices)

    cond do
      new_key == old.modifier_key ->
        {:ok, old}

      old.quantity > 1 ->
        in_transaction(fn ->
          old |> Ecto.Changeset.change(quantity: old.quantity - 1) |> Repo.update!()
          upsert_item!(old.cart_id, old.product_id, 1, choices)
        end)

      existing_item?(old, new_key) ->
        in_transaction(fn ->
          Repo.delete!(old)
          upsert_item!(old.cart_id, old.product_id, old.quantity, choices)
        end)

      true ->
        old
        |> Ecto.Changeset.change(
          modifiers: Enum.map(choices, &%{"id" => &1.id, "quantity" => &1.quantity}),
          modifier_key: new_key
        )
        |> Repo.update()
    end
  end

  defp existing_item?(old, modifier_key) do
    Repo.exists?(
      from(ci in CartItem,
        where:
          ci.cart_id == ^old.cart_id and ci.product_id == ^old.product_id and
            ci.modifier_key == ^modifier_key
      )
    )
  end

  defp upsert_item!(cart_id, product_id, quantity, choices) do
    case upsert_item(cart_id, product_id, quantity, choices) do
      {:ok, item} -> item
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp in_transaction(fun) do
    case Repo.transaction(fun) do
      {:ok, item} -> {:ok, item}
      {:error, reason} -> {:error, reason}
    end
  end

  def add_items(cart_id, lines) do
    with %Cart{} = cart <- Repo.get(Cart, cart_id) || {:error, :cart_not_found} do
      Enum.each(lines, fn line ->
        {product_id, quantity, modifiers} = line_parts(line)

        with {:ok, uuid} <- available_product(product_id, cart.branch_id),
             {:ok, choices} <- choose(uuid, cart.branch_id, modifiers),
             do: upsert_item(cart.id, uuid, quantity, choices)
      end)

      {:ok, recalculate_and_cache(cart)}
    end
  end

  defp line_parts({product_id, quantity}), do: {product_id, quantity, nil}
  defp line_parts({product_id, quantity, modifiers}), do: {product_id, quantity, modifiers}

  defp choose(_product_id, _branch_id, :as_sold), do: {:ok, []}

  defp choose(product_id, branch_id, modifiers) do
    groups = Map.get(Modifiers.for_products([product_id]), product_id, [])
    stopped = if branch_id, do: Modifiers.stopped_ids(branch_id), else: MapSet.new()

    case {groups, modifiers} do
      {[], selection} when selection in [nil, []] -> {:ok, []}
      {[], _selection} -> {:error, :modifier_unavailable}
      _ -> Modifiers.resolve(groups, modifiers, stopped)
    end
  end

  def item_key(product_id, ""), do: product_id
  def item_key(product_id, modifier_key), do: product_id <> "~" <> modifier_key

  def parse_item_key(key) when is_binary(key) do
    case String.split(key, "~", parts: 2) do
      [product_id, modifier_key] -> {product_id, modifier_key}
      [product_id] -> {product_id, ""}
    end
  end

  defp stopped?(nil, _product_id), do: false
  defp stopped?(branch_id, product_id), do: Net.Stops.stopped?(branch_id, product_id)

  defp available_product(product_id, branch_id) do
    with {:ok, uuid} <- Ecto.UUID.cast(product_id),
         true <- Net.product_available_in_branch?(uuid, branch_id),
         false <- stopped?(branch_id, uuid) do
      {:ok, uuid}
    else
      _ -> {:error, :product_unavailable}
    end
  end

  defp upsert_item(cart_id, product_id, quantity, choices) do
    now = DateTime.utc_now(:second)

    increment =
      from(ci in CartItem,
        where: ci.quantity + ^quantity <= ^CartItem.max_quantity(),
        update: [inc: [quantity: ^quantity], set: [updated_at: ^now]]
      )

    %CartItem{}
    |> CartItem.changeset(%{
      cart_id: cart_id,
      product_id: product_id,
      quantity: quantity,
      modifiers: Enum.map(choices, &%{"id" => &1.id, "quantity" => &1.quantity}),
      modifier_key: Modifiers.key(choices)
    })
    |> Repo.insert(
      on_conflict: increment,
      conflict_target: [:cart_id, :product_id, :modifier_key],
      stale_error_field: :quantity
    )
    |> case do
      {:error, %Ecto.Changeset{errors: [quantity: _error]}} ->
        {:error, :quantity_limit_exceeded}

      result ->
        result
    end
  end

  def remove_item(cart_id, key, opts \\ []) do
    delete_all? = Keyword.get(opts, :all, false)
    {product_id, modifier_key} = parse_item_key(key)

    base_query =
      from(ci in CartItem,
        where:
          ci.cart_id == ^cart_id and ci.product_id == ^product_id and
            ci.modifier_key == ^modifier_key
      )

    status =
      if delete_all? do
        case Repo.delete_all(base_query) do
          {0, _} -> {:error, :not_found}
          {_, _} -> {:ok, :deleted}
        end
      else
        query_decrement = from(ci in base_query, where: ci.quantity > 1)

        case Repo.update_all(query_decrement, inc: [quantity: -1]) do
          {1, _} ->
            {:ok, :updated}

          {0, _} ->
            case Repo.delete_all(base_query) do
              {0, _} -> {:error, :not_found}
              {_, _} -> {:ok, :deleted}
            end
        end
      end

    case status do
      {:ok, result} ->
        cart_view = refresh_and_cache(cart_id)
        {:ok, result, cart_view}

      error ->
        error
    end
  end

  def delete_cart(%Cart{} = cart) do
    Repo.transaction(fn ->
      case Repo.delete(cart) do
        {:ok, deleted_cart} ->
          Cachex.del(@cache_store, deleted_cart.id)
          deleted_cart

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  def delete_cart(cart_id) when is_integer(cart_id) or is_binary(cart_id) do
    case Repo.get(Cart, cart_id) do
      %Cart{} = cart -> delete_cart(cart)
      nil -> {:error, :not_found}
    end
  end

  def build_cart_view(cart_id) when is_integer(cart_id) or is_binary(cart_id) do
    case Repo.get(Cart, cart_id) do
      nil -> nil
      cart -> build_cart_view(cart)
    end
  end

  def build_cart_view(%Cart{} = cart) do
    cart = Repo.preload(cart, :items)
    build_cart_view(cart, cart.items)
  end

  defp build_cart_view(%Cart{} = cart, items) when is_list(items) do
    product_ids = Enum.map(items, & &1.product_id) |> Enum.uniq()
    products_map = Net.list_products_by_ids(product_ids, preload: [:media])
    groups = Modifiers.for_products(product_ids)

    {view_items, total_qty, total_amt, inactive_item_ids} =
      Enum.reduce(items, {[], 0, 0, []}, fn item, {acc_items, acc_qty, acc_amt, inactive_acc} ->
        case Map.get(products_map, item.product_id) do
          nil ->
            {acc_items, acc_qty, acc_amt, [item.id | inactive_acc]}

          product ->
            choices = current_choices(item, Map.get(groups, item.product_id, []))

            if product.is_active && is_nil(product.deleted_at) && choices != :gone do
              price = product.price + Modifiers.price(choices)
              item_total = price * item.quantity

              view_item = %{
                key: item_key(item.product_id, item.modifier_key),
                product_id: item.product_id,
                name: product.name,
                image_url: Delivest.Media.thumb_url_from_file(product.media),
                price: price,
                quantity: item.quantity,
                total_price: item_total,
                modifiers: choices
              }

              {[view_item | acc_items], acc_qty + item.quantity, acc_amt + item_total,
               inactive_acc}
            else
              {acc_items, acc_qty, acc_amt, [item.id | inactive_acc]}
            end
        end
      end)

    if length(inactive_item_ids) > 0 do
      from(ci in CartItem,
        where: ci.cart_id == ^cart.id and ci.id in ^inactive_item_ids
      )
      |> Repo.delete_all()
    end

    %CartView{
      id: cart.id,
      session_id: cart.session_id,
      staff_id: cart.staff_id,
      branch_id: cart.branch_id,
      client_id: cart.client_id,
      fulfillment_type: cart.fulfillment_type,
      promo_code: cart.promo_code,
      items: Enum.reverse(view_items),
      total_quantity: total_qty,
      subtotal_amount: total_amt,
      total_amount: total_amt
    }
  end

  defp current_choices(%CartItem{modifiers: []}, _groups), do: []

  defp current_choices(%CartItem{modifiers: modifiers}, groups) do
    case Modifiers.resolve(groups, modifiers) do
      {:ok, choices} -> choices
      {:error, _reason} -> :gone
    end
  end

  def update_context(cart_id, attrs) do
    case Repo.get(Cart, cart_id) do
      %Cart{} = cart ->
        cart
        |> Cart.context_changeset(attrs)
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:ok, recalculate_and_cache(updated)}
          error -> error
        end

      nil ->
        {:error, :cart_not_found}
    end
  end

  def detach_cart(%CartView{id: cart_id}) do
    detach_cart(cart_id)
  end

  def detach_cart(%Cart{id: cart_id}) do
    detach_cart(cart_id)
  end

  def detach_cart(cart_id) when is_integer(cart_id) or is_binary(cart_id) do
    case Repo.get(Cart, cart_id) do
      %Cart{} = cart ->
        case cart |> Cart.changeset(%{session_id: nil, staff_id: nil}) |> Repo.update() do
          {:ok, updated_cart} ->
            cart_view = refresh_and_cache(updated_cart.id)
            {:ok, cart_view}

          {:error, changeset} ->
            {:error, changeset}
        end

      nil ->
        {:error, :not_found}
    end
  end

  defp fetch_cached_or_recalculate(cart_id, force?) do
    if force? do
      fetch_and_recalculate(cart_id)
    else
      case Cachex.get(@cache_store, cart_id) do
        {:ok, %CartView{} = cached_view} -> CartPricing.apply(cached_view)
        _ -> fetch_and_recalculate(cart_id)
      end
    end
  end

  defp fetch_and_recalculate(cart_id) do
    case Repo.get(Cart, cart_id) do
      %Cart{} = cart -> recalculate_and_cache(cart)
      nil -> nil
    end
  end

  defp refresh_and_cache(cart_id) do
    fetch_and_recalculate(cart_id)
  end

  defp recalculate_and_cache(%Cart{} = cart) do
    cart_view = build_cart_view(cart)
    Cachex.put(@cache_store, cart.id, cart_view, ttl: @cache_ttl)
    CartPricing.apply(cart_view)
  end

  defp fetch_raw_cart(opts) do
    session_id = Keyword.get(opts, :session_id)
    staff_id = Keyword.get(opts, :staff_id)
    branch_id = Keyword.get(opts, :branch_id)

    cond do
      not is_nil(session_id) ->
        query =
          from c in Cart,
            where: c.session_id == ^session_id,
            order_by: [desc: c.updated_at, desc: c.inserted_at],
            limit: 1

        query = if branch_id, do: from(c in query, where: c.branch_id == ^branch_id), else: query
        Repo.one(query)

      not is_nil(staff_id) ->
        query =
          from c in Cart,
            where: c.staff_id == ^staff_id,
            order_by: [desc: c.inserted_at],
            limit: 1

        query = if branch_id, do: from(c in query, where: c.branch_id == ^branch_id), else: query

        Repo.one(query)

      true ->
        nil
    end
  end
end
