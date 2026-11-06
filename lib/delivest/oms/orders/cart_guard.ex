defmodule Delivest.Oms.Orders.CartGuard do
  import Ecto.Query, warn: false

  alias Delivest.Oms.{Cart, CartView, Carts, Order}
  alias Delivest.Net.Products
  alias Delivest.Promo.{Catalog, Strategy}
  alias Delivest.Repo

  def acquire(cart_id, branch_id, order_id \\ nil) do
    with {:ok, cart_id} <- cast_id(cart_id),
         {:ok, {locked_cart, version}} <- lock(cart_id),
         :ok <- ensure_not_ordered(cart_id, order_id),
         {:ok, cart} <- fetch(locked_cart, version),
         :ok <- ensure_branch(cart, branch_id) do
      {:ok, cart}
    end
  end

  defp cast_id(cart_id) do
    case Ecto.UUID.cast(cart_id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :cart_not_found}
    end
  end

  defp lock(cart_id) do
    query =
      from(c in Cart,
        left_join: b in Delivest.Identity.Branch,
        on: b.id == c.branch_id,
        where: c.id == ^cart_id,
        lock: "FOR UPDATE OF c0",
        select: {c, b.catalog_version}
      )

    case Repo.one(query) do
      {%Cart{}, _version} = locked -> {:ok, locked}
      nil -> {:error, :cart_not_found}
    end
  end

  defp ensure_not_ordered(cart_id, order_id) do
    query = from(o in Order, where: o.cart_id == ^cart_id)
    query = if order_id, do: where(query, [o], o.id != ^order_id), else: query

    if Repo.exists?(query), do: {:error, :cart_already_ordered}, else: :ok
  end

  defp fetch(%Cart{branch_id: nil}, _version), do: {:error, :cart_branch_mismatch}

  defp fetch(cart, version) do
    cart = Repo.preload(cart, :items)
    ids = Enum.map(cart.items, & &1.product_id)
    compiled = Catalog.list(cart.branch_id, version)
    slugs = compiled |> Enum.flat_map(&Strategy.slugs(&1.strategy)) |> Enum.uniq()
    products = Products.list_branch_products_by_refs(cart.branch_id, ids, slugs)

    if Enum.any?(ids, &(not Map.has_key?(products, &1))) do
      {:error, :product_unavailable}
    else
      case Carts.build_cart_view(cart, products) do
        %CartView{items: []} ->
          {:error, :cart_is_empty}

        %CartView{items: items} when length(items) != length(ids) ->
          {:error, :product_unavailable}

        %CartView{} = view ->
          {:ok,
           %{
             view
             | product_snapshot: products,
               compiled_promotions: compiled,
               catalog_version: version
           }}
      end
    end
  end

  defp ensure_branch(_cart, nil), do: :ok
  defp ensure_branch(%CartView{branch_id: branch_id}, branch_id), do: :ok
  defp ensure_branch(_cart, _branch_id), do: {:error, :cart_branch_mismatch}
end
