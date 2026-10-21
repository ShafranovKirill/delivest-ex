defmodule Delivest.Net.Products do
  import Ecto.Query

  alias Delivest.Net.Product
  alias Ecto.Multi
  alias Delivest.{Repo, Identity, Relations}
  alias Delivest.Audit
  alias Delivest.Relations.EntityRelation

  def list_staff_products_for_branch(staff, branch_id, params \\ %{}, opts \\ []) do
    if Identity.can?(staff, "products.read") do
      product_ids = Relations.list_target_ids("Branch", branch_id, "Product")

      Product
      |> where([p], p.id in ^product_ids)
      |> where([p], is_nil(p.deleted_at))
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
      |> Multi.insert(:product, %Product{} |> Product.changeset(attrs) |> put_slug())
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
          {:error, error}
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

    with {:ok, product} <- %Product{} |> Product.changeset(attrs) |> put_slug() |> Repo.insert(),
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
      updateble_product
      |> Product.changeset(attrs)
      |> put_slug()
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

  defp maybe_preload_query(query, opts) do
    case Keyword.get(opts, :preload) do
      nil -> query
      preloads -> preload(query, ^preloads)
    end
  end
end
