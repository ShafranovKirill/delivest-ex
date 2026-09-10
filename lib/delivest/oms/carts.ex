defmodule Delivest.Carts do
  import Ecto.Query, warn: false

  alias Delivest.{Repo, Net}
  alias Delivest.Oms.{Cart, CartItem, CartView}

  @cache_store :cart_cache

  def get_cart(opts) when is_list(opts) do
    force? = Keyword.get(opts, :force, false)

    case fetch_raw_cart(opts) do
      nil ->
        nil

      %Cart{} = cart ->
        cache_key = cache_key(cart.id)

        if force? do
          recalculate_and_cache(cart, cache_key)
        else
          case Cachex.get(@cache_store, cache_key) do
            {:ok, %CartView{} = cached_view} ->
              cached_view

            _ ->
              recalculate_and_cache(cart, cache_key)
          end
        end
    end
  end

  def add_item(cart_id, product_id) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    changeset =
      %CartItem{}
      |> CartItem.changeset(%{
        cart_id: cart_id,
        product_id: product_id,
        quantity: 1
      })

    result =
      Repo.insert(
        changeset,
        on_conflict: [inc: [quantity: 1], set: [updated_at: now]],
        conflict_target: [:cart_id, :product_id],
        returning: true
      )

    case result do
      {:ok, item} ->
        cart_view = refresh_and_cache(cart_id)
        {:ok, item, cart_view}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def remove_item(cart_id, product_id, opts \\ []) do
    delete_all? = Keyword.get(opts, :all, false)

    query =
      from(ci in CartItem,
        where: ci.cart_id == ^cart_id and ci.product_id == ^product_id
      )

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      %CartItem{} = item ->
        if delete_all? or item.quantity <= 1 do
          Repo.delete(item)
        else
          item
          |> CartItem.changeset(%{quantity: item.quantity - 1})
          |> Repo.update()
        end
        |> case do
          {:ok, result} ->
            cart_view = refresh_and_cache(cart_id)
            {:ok, result, cart_view}

          error ->
            error
        end
    end
  end

  # Сборка корзины по cart_id без загрузки полной структуры %Cart{}
  def build_cart_view(cart_id) when is_integer(cart_id) or is_binary(cart_id) do
    cart = Repo.get(Cart, cart_id)

    if cart do
      items = Repo.all(from(ci in CartItem, where: ci.cart_id == ^cart.id))
      build_cart_view(cart, items)
    else
      nil
    end
  end

  def build_cart_view(%Cart{} = cart) do
    items = Repo.all(from(ci in CartItem, where: ci.cart_id == ^cart.id))
    build_cart_view(cart, items)
  end

  def build_cart_view(%Cart{} = cart, items) when is_list(items) do
    product_ids =
      items
      |> Enum.map(& &1.product_id)
      |> Enum.uniq()

    products_map = Net.list_products_by_ids(product_ids, preload: [:media])

    {view_items, total_qty, total_amt} =
      Enum.reduce(items, {[], 0, 0}, fn item, {acc_items, acc_qty, acc_amt} ->
        case Map.get(products_map, item.product_id) do
          nil ->
            {acc_items, acc_qty, acc_amt}

          product ->
            item_total = product.price * item.quantity

            view_item = %{
              product_id: item.product_id,
              name: product.name,
              image_url: Delivest.Media.get_url_from_file(product.media),
              price: product.price,
              quantity: item.quantity,
              total_price: item_total
            }

            {
              [view_item | acc_items],
              acc_qty + item.quantity,
              acc_amt + item_total
            }
        end
      end)

    %CartView{
      id: cart.id,
      session_id: cart.session_id,
      staff_id: cart.staff_id,
      branch_id: cart.branch_id,
      items: Enum.reverse(view_items),
      total_quantity: total_qty,
      total_amount: total_amt
    }
  end

  defp refresh_and_cache(cart_id) do
    case build_cart_view(cart_id) do
      %CartView{} = cart_view ->
        Cachex.put(@cache_store, cache_key(cart_id), cart_view, ttl: :timer.hours(24))
        cart_view

      nil ->
        nil
    end
  end

  defp recalculate_and_cache(%Cart{} = cart, cache_key) do
    cart_view = build_cart_view(cart)
    Cachex.put(@cache_store, cache_key, cart_view, ttl: :timer.hours(24))
    cart_view
  end

  defp fetch_raw_cart(opts) do
    query = from(c in Cart)

    case {Keyword.get(opts, :session_id), Keyword.get(opts, :staff_id)} do
      {session_id, _} when not is_nil(session_id) ->
        Repo.get_by(query, session_id: session_id)

      {_, staff_id} when not is_nil(staff_id) ->
        Repo.get_by(query, staff_id: staff_id)

      _ ->
        nil
    end
  end

  defp cache_key(cart_id), do: "cart:#{cart_id}"
end
