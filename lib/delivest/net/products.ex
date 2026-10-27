defmodule Delivest.Net.Products do
  import Ecto.Query

  alias Delivest.Net.{Product, ProductCrmIds}
  alias Ecto.Multi
  alias Delivest.{Repo, Identity, Relations}
  alias Delivest.Audit
  alias Delivest.Integrations.Channels
  alias Delivest.Relations.EntityRelation

  def list_staff_products_for_branch(staff, branch_id, params \\ %{}, opts \\ []) do
    if Identity.can?(staff, "products.read") do
      product_ids = Relations.list_target_ids("Branch", branch_id, "Product")

      Product
      |> where([p], p.id in ^product_ids)
      |> where([p], is_nil(p.deleted_at))
      |> only_ids(Keyword.get(opts, :only_ids))
      |> maybe_preload_query(opts)
      |> Flop.validate_and_run(params, for: Product)
    else
      {:error, :forbidden}
    end
  end

  def list_branch_products(branch_id) do
    product_ids = Relations.list_target_ids("Branch", branch_id, "Product")

    Product
    |> where([p], p.id in ^product_ids and is_nil(p.deleted_at) and p.is_active == true)
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  def list_products_by_ids(ids, opts \\ []) when is_list(ids) do
    if ids == [] do
      %{}
    else
      Product
      |> where([p], p.id in ^ids)
      |> where([p], is_nil(p.deleted_at))
      |> where([p], p.is_active == true)
      |> maybe_preload_query(opts)
      |> Repo.all()
      |> Map.new(fn product -> {product.id, product} end)
    end
  end

  def product_available_in_branch?(product_id, nil),
    do: product_id |> available_query() |> Repo.exists?()

  def product_available_in_branch?(product_id, branch_id) do
    product_id
    |> available_query()
    |> join(:inner, [p], r in EntityRelation,
      on:
        r.to_id == p.id and r.to_entity_type == "Product" and
          r.from_entity_type == "Branch" and r.from_id == ^branch_id
    )
    |> Repo.exists?()
  end

  defp available_query(product_id) do
    from(p in Product,
      where: p.id == ^product_id and p.is_active == true and is_nil(p.deleted_at)
    )
  end

  def get_product(id, opts \\ []) do
    Product
    |> where([p], is_nil(p.deleted_at))
    |> maybe_preload_query(opts)
    |> Repo.get(id)
  end

  def create_product(staff, branch_id, attrs) do
    staff
    |> do_create_product(branch_id, attrs)
    |> Audit.track(staff, "product.created", branch_id: branch_id)
  end

  defp do_create_product(staff, branch_id, attrs) do
    if Identity.can?(staff, "products.create") do
      Multi.new()
      |> Multi.insert(
        :product,
        %Product{}
        |> Product.changeset(attrs)
        |> ProductCrmIds.put(branch_id)
        |> put_slug()
        |> put_order()
      )
      |> Multi.run(:relation_branch, fn repo, %{product: product} ->
        case Relations.create_relation(
               repo,
               "Branch",
               branch_id,
               "Product",
               product.id,
               %{}
             ) do
          {:ok, relation} -> {:ok, relation}
          {:error, reason} -> {:error, reason}
        end
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{product: created_product}} ->
          invalidate_menu_cache(branch_id)
          broadcast_change(branch_id, {:product_created, created_product})
          {:ok, created_product}

        {:error, _failed_operation, error, _changes_so_far} ->
          {:error, ProductCrmIds.lift_errors(error)}
      end
    else
      {:error, :forbidden}
    end
  end

  def import_products(staff, branch_id, rows) do
    if Identity.can?(staff, "products.create") do
      Repo.transaction(fn ->
        {products, _categories} =
          Enum.map_reduce(rows, %{}, &import_row(staff, branch_id, &1, &2))

        products
      end)
      |> case do
        {:ok, products} ->
          invalidate_menu_cache(branch_id)

          Enum.each(products, fn product ->
            broadcast_change(branch_id, {:product_created, product})
            Audit.record(staff, "product.created", product, branch_id: branch_id)
          end)

          {:ok, products}

        error ->
          error
      end
    else
      {:error, :forbidden}
    end
  end

  defp import_row(staff, branch_id, row, categories) do
    {category_id, categories} = import_category(staff, branch_id, row["category"], categories)
    attrs = row |> Map.delete("category") |> Map.put("category_id", category_id)

    with {:ok, product} <-
           %Product{}
           |> Product.changeset(attrs)
           |> ProductCrmIds.put(branch_id)
           |> put_slug()
           |> put_order()
           |> Repo.insert(),
         {:ok, _relation} <-
           Relations.create_relation(Repo, "Branch", branch_id, "Product", product.id, %{}) do
      {product, categories}
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp import_category(_staff, _branch_id, name, categories) when name in [nil, ""],
    do: {nil, categories}

  defp import_category(staff, branch_id, name, categories) do
    key = String.downcase(name)

    case Map.fetch(categories, key) do
      {:ok, id} ->
        {id, categories}

      :error ->
        case Delivest.Net.Categories.find_or_create_category_by_name(staff, branch_id, name) do
          {:ok, category} -> {category.id, Map.put(categories, key, category.id)}
          {:error, reason} -> Repo.rollback(reason)
        end
    end
  end

  def update_product(staff, %Product{} = updateble_product, attrs) do
    staff
    |> do_update_product(updateble_product, attrs)
    |> Audit.track(staff, "product.updated")
  end

  defp do_update_product(staff, %Product{} = updateble_product, attrs) do
    if Identity.can?(staff, "products.update") do
      branch_id = get_product_branch_id(updateble_product.id)

      updateble_product
      |> Repo.preload(:external_ids)
      |> Product.changeset(attrs)
      |> ProductCrmIds.put(branch_id)
      |> put_slug()
      |> put_order()
      |> Repo.update()
      |> case do
        {:ok, updated_product} ->
          invalidate_menu_cache(branch_id)
          broadcast_change(branch_id, {:product_updated, updated_product})
          {:ok, updated_product}

        {:error, changeset} ->
          {:error, ProductCrmIds.lift_errors(changeset)}
      end
    else
      {:error, :forbidden}
    end
  end

  def get_branch_product_by_slug(branch_id, slug) when is_binary(slug) do
    product_ids = Relations.list_target_ids("Branch", branch_id, "Product")

    Product
    |> where([p], p.slug == ^slug and p.id in ^product_ids)
    |> where([p], is_nil(p.deleted_at) and p.is_active == true)
    |> Repo.one()
  end

  def list_branch_products_by_slugs(_branch_id, []), do: %{}

  def list_branch_products_by_slugs(branch_id, slugs) when is_list(slugs) do
    product_ids = Relations.list_target_ids("Branch", branch_id, "Product")

    Product
    |> where([p], p.slug in ^slugs and p.id in ^product_ids)
    |> where([p], is_nil(p.deleted_at) and p.is_active == true)
    |> preload(:media)
    |> Repo.all()
    |> Map.new(&{&1.slug, &1})
  end

  def list_product_options_for_branch(branch_id) do
    product_ids = Relations.list_target_ids("Branch", branch_id, "Product")

    Product
    |> where([p], p.id in ^product_ids and is_nil(p.deleted_at))
    |> order_by([p], asc: p.name)
    |> select([p], {p.name, p.id})
    |> Repo.all()
  end

  defp put_slug(changeset) do
    case Ecto.Changeset.get_field(changeset, :slug) do
      slug when is_binary(slug) and slug != "" ->
        changeset

      _ ->
        base = Delivest.Slug.slugify(Ecto.Changeset.get_field(changeset, :name)) || "product"
        own_id = changeset.data.id

        Ecto.Changeset.put_change(
          changeset,
          :slug,
          Delivest.Slug.unique(base, &slug_taken?(&1, own_id))
        )
    end
  end

  defp slug_taken?(slug, own_id) do
    query = from(p in Product, where: p.slug == ^slug)
    query = if own_id, do: where(query, [p], p.id != ^own_id), else: query
    Repo.exists?(query)
  end

  def list_category_products(branch_id, category_id) do
    product_ids = Relations.list_target_ids("Branch", branch_id, "Product")

    Product
    |> where([p], p.id in ^product_ids and p.category_id == ^category_id)
    |> where([p], is_nil(p.deleted_at))
    |> order_by([p], asc_nulls_last: p.order, asc: p.name)
    |> preload(:media)
    |> Repo.all()
  end

  def update_product_order(staff, %Product{} = product, above_order, below_order) do
    if Identity.can?(staff, "products.update") do
      product
      |> Ecto.Changeset.change(order: calculate_new_order(above_order, below_order))
      |> Repo.update()
      |> case do
        {:ok, updated_product} ->
          branch_id = get_product_branch_id(updated_product.id)
          invalidate_menu_cache(branch_id)
          broadcast_change(branch_id, {:product_updated, updated_product})
          {:ok, updated_product}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :forbidden}
    end
  end

  defp put_order(changeset) do
    new? = is_nil(changeset.data.id)

    if new? or Ecto.Changeset.changed?(changeset, :category_id) do
      category_id = Ecto.Changeset.get_field(changeset, :category_id)
      Ecto.Changeset.put_change(changeset, :order, next_order(category_id))
    else
      changeset
    end
  end

  defp next_order(nil), do: nil

  defp next_order(category_id) do
    max_order =
      Product
      |> where([p], p.category_id == ^category_id and is_nil(p.deleted_at))
      |> select([p], max(p.order))
      |> Repo.one()

    (max_order || 0.0) + 1.0
  end

  defp calculate_new_order(above_order, below_order)
       when not is_nil(above_order) and not is_nil(below_order) do
    (above_order + below_order) / 2.0
  end

  defp calculate_new_order(nil, below_order) when not is_nil(below_order) do
    if below_order > 0.0 do
      below_order / 2.0
    else
      below_order - 1.0
    end
  end

  defp calculate_new_order(above_order, nil) when not is_nil(above_order) do
    above_order + 1.0
  end

  defp calculate_new_order(nil, nil), do: 1.0

  def soft_delete_product(staff, %Product{} = product) do
    staff
    |> do_soft_delete_product(product)
    |> Audit.track(staff, "product.deleted")
  end

  defp do_soft_delete_product(staff, %Product{} = product) do
    if Identity.can?(staff, "products.delete") do
      with {:ok, deleted_product} <-
             product
             |> Ecto.Changeset.change(%{deleted_at: DateTime.utc_now(:second)})
             |> Repo.update() do
        branch_id = get_product_branch_id(product.id)
        invalidate_menu_cache(branch_id)
        broadcast_change(branch_id, {:product_deleted, deleted_product})
        {:ok, deleted_product}
      end
    else
      {:error, :forbidden}
    end
  end

  def soft_delete_products(staff, branch_id, ids) when is_list(ids) do
    if Identity.can?(staff, "products.delete") do
      branch_product_ids = Relations.list_target_ids("Branch", branch_id, "Product")
      now = DateTime.utc_now(:second)

      {_count, deleted} =
        Product
        |> where([p], p.id in ^ids and p.id in ^branch_product_ids and is_nil(p.deleted_at))
        |> select([p], p)
        |> Repo.update_all(set: [deleted_at: now, updated_at: now])

      invalidate_menu_cache(branch_id)

      Enum.each(deleted, fn product ->
        broadcast_change(branch_id, {:product_deleted, product})
        Audit.record(staff, "product.deleted", product, branch_id: branch_id)
      end)

      {:ok, deleted}
    else
      {:error, :forbidden}
    end
  end

  def subscribe_branch(branch_id) when not is_nil(branch_id) do
    Phoenix.PubSub.subscribe(Delivest.PubSub, "branch_products:#{branch_id}")
  end

  def subscribe_branch(_), do: :ok

  defp broadcast_change(branch_id, message) when not is_nil(branch_id) do
    Phoenix.PubSub.broadcast(Delivest.PubSub, "branch_products:#{branch_id}", message)
  end

  defp broadcast_change(_, _), do: :ok

  defp get_product_branch_id(product_id) do
    Relations.list_source_ids("Product", product_id, "Branch")
    |> List.first()
  end

  defp invalidate_menu_cache(branch_id) when not is_nil(branch_id) do
    Channels.menu_changed(branch_id)
    Cachex.del(:menu_cache, branch_id)
    Cachex.del(:stock_cache, branch_id)
    Cachex.del(:promo_cache, branch_id)
    Cachex.clear(:cart_cache)
  end

  defp invalidate_menu_cache(_) do
    Cachex.clear(:stock_cache)
    Cachex.clear(:promo_cache)
    Cachex.clear(:cart_cache)
  end

  defp only_ids(query, nil), do: query
  defp only_ids(query, ids), do: where(query, [p], p.id in ^ids)

  defp maybe_preload_query(query, opts) do
    case Keyword.get(opts, :preload) do
      nil -> query
      preloads -> preload(query, ^preloads)
    end
  end
end
