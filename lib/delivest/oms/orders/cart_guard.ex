defmodule Delivest.Oms.Orders.CartGuard do
  import Ecto.Query, warn: false

  alias Delivest.Oms.{Cart, CartItem, CartRevision, CartView, Carts, Order}
  alias Delivest.Net.Products
  alias Delivest.Integrations.Crm
  alias Delivest.Promo.{Catalog, Strategy}
  alias Delivest.Repo

  def acquire(cart_id, branch_id, order_id \\ nil, opts \\ []) do
    with {:ok, cart_id} <- cast_id(cart_id),
         {:ok, {locked_cart, version}} <- lock(cart_id),
         epoch <- lock_epoch(),
         :ok <- ensure_owner(locked_cart, opts),
         :ok <- ensure_epoch(epoch),
         {:ok, items} <- lock_items(cart_id),
         :ok <- ensure_revision(locked_cart, version, items, epoch, opts),
         :ok <- ensure_not_ordered(cart_id, order_id),
         :ok <- ensure_branch(locked_cart, branch_id),
         :ok <- ensure_combo_route(locked_cart, items, opts),
         {:ok, cart} <- fetch(%{locked_cart | items: items}, version),
         :ok <- ensure_guest_rewards(cart, opts) do
      {:ok, cart}
    end
  end

  defp ensure_combo_route(%Cart{branch_id: nil}, _items, _opts), do: :ok

  defp ensure_combo_route(cart, items, opts) do
    ids = Enum.map(items, & &1.product_id)

    if ids == [] do
      :ok
    else
      branch = Repo.get(Delivest.Identity.Branch, cart.branch_id)
      branch = if branch, do: Repo.preload(branch, :info)

      if opts[:crm] || (branch && Crm.provider_for(branch, Keyword.get(opts, :source, "app"))) do
        products = Products.list_branch_cart_products_by_ids(cart.branch_id, ids)

        if Enum.any?(items, fn item -> match?(%{is_combo: true}, products[item.product_id]) end),
          do: {:error, :combo_requires_delivest},
          else: :ok
      else
        :ok
      end
    end
  end

  defp lock_items(cart_id) do
    {:ok,
     Repo.all(
       from ci in CartItem,
         where: ci.cart_id == ^cart_id,
         order_by: [asc: ci.inserted_at, asc: ci.id],
         lock: "FOR UPDATE NOWAIT"
     )}
  rescue
    error in Postgrex.Error ->
      if error.postgres && error.postgres.code == :lock_not_available,
        do: {:error, :cart_changed},
        else: reraise(error, __STACKTRACE__)
  end

  defp ensure_revision(cart, version, items, epoch, opts) do
    if is_nil(opts[:cart_revision]) or
         opts[:cart_revision] == CartRevision.from_raw(cart, version, items, epoch),
       do: :ok,
       else: {:error, :cart_changed}
  end

  defp ensure_epoch(epoch) when is_binary(epoch) and byte_size(epoch) > 0, do: :ok
  defp ensure_epoch(_epoch), do: {:error, :cart_changed}

  defp ensure_owner(%Cart{session_id: session_id}, opts) do
    if not Keyword.has_key?(opts, :public_session_id) or
         (is_binary(session_id) and session_id == opts[:public_session_id]),
       do: :ok,
       else: {:error, :cart_not_found}
  end

  defp ensure_guest_rewards(cart, opts) do
    if opts[:public_guest] == true and CartView.star_items(cart) != [],
      do: {:error, :points_unavailable},
      else: :ok
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

  defp lock_epoch do
    Repo.one(from e in "storefront_epoch", select: field(e, :epoch), lock: "FOR SHARE")
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
          if Enum.any?(view.items, &Map.get(&1, :unavailable, false)) do
            {:error, :product_unavailable}
          else
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
  end

  defp ensure_branch(_cart, nil), do: :ok
  defp ensure_branch(%Cart{branch_id: branch_id}, branch_id), do: :ok
  defp ensure_branch(_cart, _branch_id), do: {:error, :cart_branch_mismatch}
end
