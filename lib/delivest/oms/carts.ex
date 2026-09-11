defmodule Delivest.Oms.Carts do
  import Ecto.Query, warn: false

  alias Delivest.{Repo, Net}
  alias Delivest.Oms.{Cart, CartItem, CartView}

  @cache_store :cart_cache
  @cache_ttl :timer.hours(24)

  def get_or_create_cart(opts) when is_list(opts) do
    case get_cart(opts) do
      %CartView{} = cart_view ->
        {:ok, cart_view}

      nil ->
        create_cart(opts)
    end
  end

  def get_cart(opts) when is_list(opts) do
    force? = Keyword.get(opts, :force, false)

    with %Cart{} = cart <- fetch_raw_cart(opts) do
      if force? do
        recalculate_and_cache(cart)
      else
        case Cachex.get(@cache_store, cart.id) do
          {:ok, %CartView{} = cached_view} -> cached_view
          _ -> recalculate_and_cache(cart)
        end
      end
    end
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

    base_query =
      from(ci in CartItem,
        where: ci.cart_id == ^cart_id and ci.product_id == ^product_id
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

  def build_cart_view(cart_id) when is_integer(cart_id) or is_binary(cart_id) do
    Cart
    |> Repo.get(cart_id)
    |> case do
      nil -> nil
      cart -> build_cart_view(cart)
    end
  end

  def build_cart_view(%Cart{} = cart) do
    cart = Repo.preload(cart, :items)
    build_cart_view(cart, cart.items)
  end

  def build_cart_view(%Cart{} = cart, items) when is_list(items) do
    product_ids = Enum.map(items, & &1.product_id) |> Enum.uniq()
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

            {[view_item | acc_items], acc_qty + item.quantity, acc_amt + item_total}
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
        Cachex.put(@cache_store, cart_id, cart_view, ttl: @cache_ttl)
        cart_view

      nil ->
        nil
    end
  end

  defp recalculate_and_cache(%Cart{} = cart) do
    cart_view = build_cart_view(cart)
    Cachex.put(@cache_store, cart.id, cart_view, ttl: @cache_ttl)
    cart_view
  end

  defp fetch_raw_cart(opts) do
    session_id = Keyword.get(opts, :session_id)
    staff_id = Keyword.get(opts, :staff_id)

    cond do
      not is_nil(session_id) -> Repo.get_by(Cart, session_id: session_id)
      not is_nil(staff_id) -> Repo.get_by(Cart, staff_id: staff_id)
      true -> nil
    end
  end
end
