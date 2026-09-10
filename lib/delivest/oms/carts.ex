defmodule Delivest.Carts do
  import Ecto.Query, warn: false

  alias Delivest.Oms.CartView
  alias Delivest.{Repo, Net}
  alias Delivest.Oms.{Cart, CartItem}

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

  def add_item(%Cart{} = cart, product_id) do
    result =
      case Repo.get_by(CartItem, cart_id: cart.id, product_id: product_id) do
        nil ->
          %CartItem{}
          |> CartItem.changeset(%{
            cart_id: cart.id,
            product_id: product_id,
            quantity: 1
          })
          |> Repo.insert()

        %CartItem{} = item ->
          item
          |> CartItem.changeset(%{quantity: item.quantity + 1})
          |> Repo.update()
      end

    case result do
      {:ok, _updated_item} = success ->
        invalidate_cache(cart.id)
        success

      error ->
        error
    end
  end

  def remove_item(%Cart{} = cart, product_id, opts \\ []) do
    delete_all? = Keyword.get(opts, :all, false)

    result =
      case Repo.get_by(CartItem, cart_id: cart.id, product_id: product_id) do
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
      end

    case result do
      {:ok, _} = success ->
        invalidate_cache(cart.id)
        success

      error ->
        error
    end
  end

  def build_cart_view(%Cart{} = cart) do
    product_ids =
      cart.items
      |> Enum.map(& &1.product_id)
      |> Enum.uniq()

    products_map = Net.list_products_by_ids(product_ids, preload: [:media])

    {items, total_qty, total_amt} =
      Enum.reduce(cart.items, {[], 0, 0}, fn item, {acc_items, acc_qty, acc_amt} ->
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
      items: Enum.reverse(items),
      total_quantity: total_qty,
      total_amount: total_amt
    }
  end

  defp recalculate_and_cache(%Cart{} = cart, cache_key) do
    cart_view = build_cart_view(cart)
    Cachex.put(@cache_store, cache_key, cart_view, ttl: :timer.hours(24))
    cart_view
  end

  defp fetch_raw_cart(opts) do
    session_id = Keyword.get(opts, :session_id)
    staff_id = Keyword.get(opts, :staff_id)

    query = from(c in Cart, preload: [:items])

    cond do
      not is_nil(session_id) ->
        Repo.one(from c in query, where: c.session_id == ^session_id)

      not is_nil(staff_id) ->
        Repo.one(from c in query, where: c.staff_id == ^staff_id)

      true ->
        nil
    end
  end

  defp cache_key(cart_id), do: cart_id

  defp invalidate_cache(cart_id) do
    Cachex.del(@cache_store, cache_key(cart_id))
  end
end
