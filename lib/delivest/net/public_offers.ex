defmodule Delivest.Net.PublicOffers do
  @moduledoc "Branch-scoped public catalog projection shared by menu, direct entry and feeds."
  import Ecto.Query

  alias Delivest.{Identity, Net, Popular, Promo, Repo}
  alias Delivest.Integrations.Crm
  alias Delivest.Net.ComboAvailability

  alias Delivest.Net.{
    Catalogs,
    Category,
    MenuView,
    ModifierStop,
    Product,
    ProductStop,
    ProductTag
  }

  alias Delivest.Relations.EntityRelation
  alias Delivest.Net.PublicOffer

  @batch_size 200

  def menu(branch_id) do
    with {:ok, _} <- active_branch(branch_id),
         {:ok, categories} <- Net.get_menu_for_branch(branch_id) do
      {:ok, decorate(categories, branch_id)}
    end
  end

  def menu_fresh(branch_id) do
    with {:ok, uuid} <- Ecto.UUID.cast(branch_id),
         true <-
           Repo.exists?(
             from(b in Delivest.Identity.Branch,
               where: b.id == ^uuid and b.is_active and is_nil(b.deleted_at)
             )
           ),
         {:ok, categories} <- Catalogs.get_menu_uncached_for_branch(uuid) do
      {:ok, decorate(categories, uuid, false, true)}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Build a fresh menu for a branch already checked against the storefront branch revision."
  def menu_fresh_known_active(branch_id, stops) do
    with {:ok, uuid} <- Ecto.UUID.cast(branch_id),
         {:ok, categories} <- Catalogs.get_menu_uncached_for_branch(uuid) do
      {:ok, decorate(categories, uuid, false, true, stops)}
    end
  end

  @doc "One branch-scoped stop snapshot supplies both menu decoration and its next expiry."
  def stop_snapshot(branch_id) do
    now = DateTime.utc_now()

    products =
      Repo.all(
        from(s in ProductStop,
          where: s.branch_id == ^branch_id and (is_nil(s.until) or s.until > ^now),
          select: {s.product_id, s.until}
        )
      )

    modifiers =
      Repo.all(
        from(s in ModifierStop,
          where: s.branch_id == ^branch_id and (is_nil(s.until) or s.until > ^now),
          select: {s.modifier_id, s.until}
        )
      )

    boundary =
      (products ++ modifiers)
      |> Enum.map(&elem(&1, 1))
      |> Enum.reject(&is_nil/1)
      |> Enum.min_by(&DateTime.to_unix(&1, :millisecond), fn -> nil end)

    %{
      products: products |> Enum.map(&elem(&1, 0)) |> MapSet.new(),
      modifiers: modifiers |> Enum.map(&elem(&1, 0)) |> MapSet.new(),
      boundary: boundary
    }
  end

  def product(branch_id, key) when is_binary(key) do
    with {:ok, _branch} <- active_branch(branch_id),
         %Product{} = product <- find_product(branch_id, key) do
      tags = tags_for([product])
      projection = MenuView.build_product(product, tags)
      category = %{id: product.category_id, products: [projection]}

      case decorate([category], branch_id, true) do
        [%{products: [offer]}] -> {:ok, offer}
        _ -> {:error, :not_found}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  def product(_branch_id, _key), do: {:error, :not_found}

  def product_exists?(branch_id, key) when is_binary(key) do
    query = product_query(branch_id)

    query =
      case Ecto.UUID.cast(key) do
        {:ok, id} -> where(query, [p], p.id == ^id)
        :error -> where(query, [p], p.slug == ^key)
      end

    Repo.exists?(query)
  end

  def active_branch(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         {:ok, %{is_active: true} = branch} <- Identity.get_branch(uuid) do
      {:ok, branch}
    else
      _ -> {:error, :not_found}
    end
  end

  def category(branch_id, key) do
    with {:ok, _} <- active_branch(branch_id),
         {:ok, uuid} <- Ecto.UUID.cast(key),
         %Category{} = category <-
           Repo.one(category_query(branch_id) |> where([c], c.id == ^uuid)) do
      {:ok, category}
    else
      _ -> {:error, :not_found}
    end
  end

  def categories(branch_id), do: Repo.all(category_query(branch_id) |> order_by([c], c.id))

  def category_preview(branch_id, category_id) do
    products =
      branch_id
      |> product_query()
      |> where([p], p.category_id == ^category_id)
      |> order_by([p], p.id)
      |> limit(@batch_size)
      |> preload(:media)
      |> Repo.all()

    tags = tags_for(products)

    [%{products: offers}] =
      decorate(
        [%{id: category_id, products: Enum.map(products, &MenuView.build_product(&1, tags))}],
        branch_id,
        true
      )

    offers
  end

  def sitemap_count(branch_id), do: Repo.aggregate(product_query(branch_id), :count)

  def sitemap_products(branch_id, page) when is_integer(page) and page >= 0 do
    branch_id
    |> product_query()
    |> order_by([p], p.id)
    |> offset(^(page * 1000))
    |> limit(1000)
    |> select([p], %{id: p.id})
    |> Repo.all()
  end

  @doc "Keyset batches avoid loading the entire branch catalog into memory."
  def batches(branch_id) do
    Stream.unfold(nil, fn
      :done ->
        nil

      cursor ->
        products =
          branch_id
          |> product_query()
          |> after_id(cursor)
          |> order_by([p], p.id)
          |> limit(@batch_size)
          |> preload(:media)
          |> Repo.all()

        case products do
          [] -> nil
          rows -> {rows, if(length(rows) < @batch_size, do: :done, else: List.last(rows).id)}
        end
    end)
    |> Stream.map(fn products ->
      tags = tags_for(products)

      categories =
        products
        |> Enum.group_by(& &1.category_id)
        |> Enum.map(fn {id, rows} ->
          %{id: id, products: Enum.map(rows, &MenuView.build_product(&1, tags))}
        end)

      decorate(categories, branch_id, true)
    end)
  end

  def product_path(branch_slug, product),
    do: "/#{URI.encode(branch_slug, &URI.char_unreserved?/1)}/product/#{product.id}"

  def category_path(branch_slug, category_id),
    do: "/#{URI.encode(branch_slug, &URI.char_unreserved?/1)}/category/#{category_id}"

  def purchasable?(offer) do
    not offer.stopped and
      (not offer.is_combo or
         (offer.modifier_groups != [] and
            Enum.all?(offer.modifier_groups, &(&1.max == 1 and &1.min in [0, 1])))) and
      Enum.all?(offer.modifier_groups, fn group ->
        capacity =
          group.modifiers
          |> Enum.reject(& &1.stopped)
          |> Enum.reduce(0, fn modifier, count ->
            count + (modifier.max_quantity || group.max || 1)
          end)

        capacity >= (group.min || 0)
      end)
  end

  defp decorate(
         categories,
         branch_id,
         load_popular? \\ false,
         fresh? \\ false,
         stop_snapshot \\ nil
       ) do
    ids = categories |> Enum.flat_map(& &1.products) |> Enum.map(& &1.id) |> Enum.uniq()
    groups = Net.Modifiers.for_products(ids)
    unavailable_components = ComboAvailability.unavailable_component_ids(branch_id, groups)

    modifier_ids =
      groups
      |> Map.values()
      |> List.flatten()
      |> Enum.flat_map(& &1.modifiers)
      |> Enum.map(& &1.id)

    now = DateTime.utc_now()

    stops =
      stop_snapshot ||
        %{
          products:
            Repo.all(
              from(s in ProductStop,
                where:
                  s.branch_id == ^branch_id and s.product_id in ^ids and
                    (is_nil(s.until) or s.until > ^now),
                select: s.product_id
              )
            )
            |> MapSet.new(),
          modifiers:
            Repo.all(
              from(s in ModifierStop,
                where:
                  s.branch_id == ^branch_id and s.modifier_id in ^modifier_ids and
                    (is_nil(s.until) or s.until > ^now),
                select: s.modifier_id
              )
            )
            |> MapSet.new()
        }

    stopped = %{
      products: stops.products,
      modifiers: stops.modifiers,
      unavailable_components: unavailable_components,
      groups: groups,
      rewards: %{}
    }

    popular = if load_popular?, do: popular_ids(branch_id, ids), else: nil
    crm_route? = crm_menu?(branch_id)

    categories
    |> then(fn values ->
      if fresh?,
        do: Promo.overlay_menu_fresh(values, branch_id),
        else: Promo.overlay_menu(values, branch_id)
    end)
    |> Enum.map(fn category ->
      Map.update!(category, :products, fn products ->
        products
        |> Enum.reject(&(Map.get(&1, :is_combo, false) and crm_route?))
        |> Enum.map(fn product ->
          product
          |> Map.put(
            :popular,
            if(popular,
              do: MapSet.member?(popular, product.id),
              else: Map.get(product, :popular, false)
            )
          )
          |> PublicOffer.data(stopped)
        end)
      end)
    end)
  end

  defp popular_ids(branch_id, ids) do
    case Popular.get_settings(branch_id) do
      %{show_in_cart: true, mode: :auto, auto_product_ids: auto} ->
        MapSet.new(auto || [])

      %{show_in_cart: true, mode: :manual} ->
        Repo.all(
          from(e in Popular.Entry,
            where: e.branch_id == ^branch_id and e.product_id in ^ids,
            select: e.product_id
          )
        )
        |> MapSet.new()

      _ ->
        MapSet.new()
    end
  end

  defp tags_for(products) do
    ids = products |> Enum.flat_map(&(&1.tags || [])) |> Enum.uniq()

    Repo.all(from(t in ProductTag, where: t.id in ^ids))
    |> Map.new(&{&1.id, %{id: &1.id, name: &1.name, icon_url: Net.ProductTags.icon_url(&1)}})
  end

  defp find_product(branch_id, key) do
    query = product_query(branch_id)

    query =
      case Ecto.UUID.cast(key) do
        {:ok, id} -> where(query, [p], p.id == ^id)
        :error -> where(query, [p], p.slug == ^key)
      end

    query |> preload(:media) |> Repo.one()
  end

  defp product_query(branch_id) do
    query =
      from(p in Product,
        join: r in EntityRelation,
        on:
          r.to_id == p.id and r.to_entity_type == "Product" and r.from_entity_type == "Branch" and
            r.from_id == ^branch_id,
        join: c in Category,
        on: c.id == p.category_id,
        join: cr in EntityRelation,
        on:
          cr.to_id == c.id and cr.to_entity_type == "Category" and cr.from_entity_type == "Branch" and
            cr.from_id == ^branch_id,
        where: p.is_active and is_nil(p.deleted_at) and c.is_active
      )

    if crm_menu?(branch_id), do: where(query, [p], not p.is_combo), else: query
  end

  defp crm_menu?(branch_id) do
    case Identity.get_branch(branch_id, preload: [:info]) do
      {:ok, branch} -> Crm.provider_for(branch, "app") != nil
      _ -> false
    end
  end

  defp category_query(branch_id) do
    from(c in Category,
      join: r in EntityRelation,
      on:
        r.to_id == c.id and r.to_entity_type == "Category" and r.from_entity_type == "Branch" and
          r.from_id == ^branch_id,
      where: c.is_active
    )
  end

  defp after_id(query, nil), do: query
  defp after_id(query, id), do: where(query, [p], p.id > ^id)
end
