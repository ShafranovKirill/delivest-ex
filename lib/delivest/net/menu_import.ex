defmodule Delivest.Net.MenuImport do
  import Ecto.Query

  alias Delivest.{Audit, Identity, Repo}
  alias Delivest.Identity.Branch
  alias Delivest.Net.{Category, Modifier, ModifierGroup, Product, ProductExternalId}
  alias Delivest.Net.ProductModifierGroup
  alias Delivest.Net.SharedOwnership
  alias Delivest.Relations.EntityRelations

  @type menu :: %{categories: [map()], products: [map()]}

  def diff(branch_id, provider, %{products: products}) do
    linked = linked(branch_id, provider, "product")

    ours =
      Repo.all(from(p in Product, where: p.id in ^Map.values(linked))) |> Map.new(&{&1.id, &1})

    seen = MapSet.new(products, & &1.external_id)

    {added, changed} =
      Enum.reduce(products, {[], []}, fn product, {added, changed} ->
        case linked |> Map.get(product.external_id) |> then(&Map.get(ours, &1)) do
          nil ->
            {[product | added], changed}

          %Product{} = our ->
            case changes(our, product) do
              [] -> {added, changed}
              fields -> {added, [%{product: product, ours: our, fields: fields} | changed]}
            end
        end
      end)

    hidden =
      linked
      |> Enum.reject(fn {external_id, _id} -> MapSet.member?(seen, external_id) end)
      |> Enum.map(fn {_external_id, id} -> Map.get(ours, id) end)
      |> Enum.filter(&match?(%Product{is_active: true, deleted_at: nil}, &1))

    %{added: Enum.reverse(added), changed: Enum.reverse(changed), hidden: hidden}
  end

  def apply(staff, branch_id, provider, %{categories: categories, products: products} = menu) do
    with :ok <- authorize_import(staff, branch_id, provider, menu) do
      provider = to_string(provider)
      plan = diff(branch_id, provider, menu)
      affected_branches = affected_branches(branch_id, provider, categories, products, plan)

      Repo.transaction(fn ->
        category_ids =
          categories
          |> Enum.with_index()
          |> Map.new(fn {category, index} ->
            {category.external_id, upsert_category(branch_id, provider, category, index)}
          end)

        linked = linked(branch_id, provider, "product")

        Enum.each(products, fn product ->
          id = upsert_product(branch_id, provider, product, linked, category_ids)
          Enum.each(Enum.with_index(product.groups), &upsert_group(branch_id, provider, id, &1))
        end)

        hidden_ids = Enum.map(plan.hidden, & &1.id)
        Repo.update_all(from(p in Product, where: p.id in ^hidden_ids), set: [is_active: false])

        Delivest.Net.Catalogs.bump_versions(affected_branches)

        %{added: length(plan.added), changed: length(plan.changed), hidden: length(hidden_ids)}
      end)
      |> tap(fn
        {:ok, summary} ->
          Enum.each(affected_branches, &invalidate/1)
          branch = Repo.get(Delivest.Identity.Branch, branch_id)
          Audit.record(staff, "menu.imported", branch, metadata: summary)

        _error ->
          :ok
      end)
    end
  end

  defp affected_branches(branch_id, provider, categories, products, plan) do
    if Enum.any?(products, &(&1.groups != [])) do
      Repo.all(from b in Branch, select: b.id)
    else
      affected_local_branches(branch_id, provider, categories, products, plan)
    end
  end

  defp affected_local_branches(branch_id, provider, categories, products, plan) do
    product_links = linked(branch_id, provider, "product")
    category_links = linked(branch_id, provider, "category")

    product_ids =
      Enum.map(products, &Map.get(product_links, &1.external_id)) ++
        Enum.map(plan.hidden, & &1.id)

    category_ids = Enum.map(categories, &Map.get(category_links, &1.external_id))

    ([branch_id] ++
       Enum.flat_map(
         Enum.reject(product_ids, &is_nil/1),
         &SharedOwnership.branches("Product", &1)
       ) ++
       Enum.flat_map(
         Enum.reject(category_ids, &is_nil/1),
         &SharedOwnership.branches("Category", &1)
       ))
    |> Enum.uniq()
  end

  defp authorize_import(
         staff,
         branch_id,
         provider,
         %{categories: categories, products: products} = menu
       ) do
    provider = to_string(provider)
    plan = diff(branch_id, provider, menu)
    linked_products = linked(branch_id, provider, "product")
    linked_categories = linked(branch_id, provider, "category")

    updated_product_ids =
      products |> Enum.map(&Map.get(linked_products, &1.external_id)) |> Enum.reject(&is_nil/1)

    updated_category_ids =
      categories
      |> Enum.map(&Map.get(linked_categories, &1.external_id))
      |> Enum.reject(&is_nil/1)

    checks =
      []
      |> maybe_require(plan.added != [], Identity.authorize(staff, "products.create", branch_id))
      |> maybe_require(
        updated_product_ids != [],
        Identity.authorize(staff, "products.update", branch_id)
      )
      |> maybe_require(plan.hidden != [], Identity.authorize(staff, "products.delete", branch_id))
      |> maybe_require(
        Enum.any?(categories, &(not Map.has_key?(linked_categories, &1.external_id))),
        Identity.authorize(staff, "categories.create", branch_id)
      )
      |> maybe_require(
        updated_category_ids != [],
        Identity.authorize(staff, "categories.update", branch_id)
      )
      |> maybe_require(
        Enum.any?(products, &(&1.groups != [])),
        if(Identity.can?(staff, "catalog.global.manage"), do: :ok, else: {:error, :forbidden})
      )

    shared_checks =
      Enum.map(
        updated_product_ids,
        &SharedOwnership.authorize(staff, "products.update", "Product", &1)
      ) ++
        Enum.map(
          plan.hidden,
          &SharedOwnership.authorize(staff, "products.delete", "Product", &1.id)
        ) ++
        Enum.map(
          updated_category_ids,
          &SharedOwnership.authorize(staff, "categories.update", "Category", &1)
        )

    if Enum.all?(checks ++ shared_checks, &(&1 == :ok)), do: :ok, else: {:error, :forbidden}
  end

  defp maybe_require(checks, true, result), do: [result | checks]
  defp maybe_require(checks, false, _result), do: checks

  defp changes(%Product{} = our, product) do
    [
      {:name, our.name, product.name},
      {:price, our.price, product.price},
      {:weight, our.weight, product[:weight]},
      {:is_active, our.is_active, true}
    ]
    |> Enum.reject(fn {_field, ours, theirs} -> is_nil(theirs) or ours == theirs end)
    |> Enum.map(&elem(&1, 0))
  end

  defp upsert_category(branch_id, provider, category, index) do
    case linked(branch_id, provider, "category") |> Map.get(category.external_id) do
      nil ->
        created =
          Repo.insert!(
            Category.changeset(%Category{is_active: true}, %{
              name: category.name,
              order: index * 1.0
            })
          )

        {:ok, _relation} =
          EntityRelations.create_relation(Repo, "Branch", branch_id, "Category", created.id)

        link(branch_id, provider, "category", created.id, category.external_id)
        created.id

      id ->
        Repo.update_all(from(c in Category, where: c.id == ^id), set: [name: category.name])
        id
    end
  end

  defp upsert_product(branch_id, provider, product, linked, category_ids) do
    attrs =
      %{
        name: product.name,
        price: product.price,
        weight: product[:weight],
        is_active: true,
        category_id: Map.get(category_ids, product[:category])
      }
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    case Map.get(linked, product.external_id) do
      nil ->
        created =
          %Product{}
          |> Product.changeset(Map.put(attrs, :slug, slug(product)))
          |> Repo.insert!()

        {:ok, _relation} =
          EntityRelations.create_relation(Repo, "Branch", branch_id, "Product", created.id)

        link(branch_id, provider, "product", created.id, product.external_id)
        created.id

      id ->
        Product |> Repo.get!(id) |> Product.changeset(attrs) |> Repo.update!()
        id
    end
  end

  defp upsert_group(branch_id, provider, product_id, {group, position}) do
    attrs = %{
      name: group.name,
      min: group[:min] || 0,
      max: max(group[:max] || 1, group[:min] || 0),
      is_size: group[:size] || false,
      is_active: true
    }

    group_id =
      case linked(branch_id, provider, "modifier_group") |> Map.get(group.external_id) do
        nil ->
          created = %ModifierGroup{} |> ModifierGroup.changeset(attrs) |> Repo.insert!()
          link(branch_id, provider, "modifier_group", created.id, group.external_id)
          created.id

        id ->
          ModifierGroup |> Repo.get!(id) |> ModifierGroup.changeset(attrs) |> Repo.update!()
          id
      end

    modifiers = linked(branch_id, provider, "modifier")

    group.modifiers
    |> Enum.with_index()
    |> Enum.each(fn {modifier, index} ->
      attrs = %{name: modifier.name, price: modifier.price, position: index, is_active: true}

      case Map.get(modifiers, modifier.external_id) do
        nil ->
          created =
            %Modifier{group_id: group_id}
            |> Modifier.changeset(Map.put(attrs, :is_default, modifier[:default] || false))
            |> Repo.insert!()

          link(branch_id, provider, "modifier", created.id, modifier.external_id)

        id ->
          Modifier |> Repo.get!(id) |> Modifier.changeset(attrs) |> Repo.update!()
      end
    end)

    Repo.insert!(
      %ProductModifierGroup{product_id: product_id, group_id: group_id, position: position},
      on_conflict: {:replace, [:position]},
      conflict_target: [:product_id, :group_id]
    )
  end

  defp linked(branch_id, provider, type) do
    Repo.all(
      from(e in ProductExternalId,
        where: e.entity_type == ^type and e.branch_id == ^branch_id,
        where: e.provider == ^to_string(provider),
        select: {e.external_id, e.entity_id}
      )
    )
    |> Map.new()
  end

  defp link(branch_id, provider, type, entity_id, external_id) do
    Repo.insert!(%ProductExternalId{
      entity_type: type,
      entity_id: entity_id,
      branch_id: branch_id,
      provider: provider,
      external_id: to_string(external_id)
    })
  end

  defp slug(product),
    do: "#{product.name}-#{product.external_id |> to_string() |> String.slice(0, 8)}"

  defp invalidate(branch_id) do
    Delivest.Net.Catalogs.invalidate_menu_cache(branch_id)
    Cachex.clear(:cart_cache)
    Cachex.del(:promo_cache, branch_id)
    Cachex.del(:stock_cache, branch_id)
  end
end
