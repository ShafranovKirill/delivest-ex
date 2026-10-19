defmodule Delivest.Repo.Migrations.AddSlugsStockProductsAndSalesIndexes do
  use Ecto.Migration

  import Ecto.Query

  def up do
    alter table(:products) do
      add :slug, :string
    end

    alter table(:stocks) do
      add :product_id, references(:products, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:stocks, [:product_id])

    alter table(:order_items) do
      add :category_id, :binary_id
      add :category_name, :string
    end

    create index(:orders, [:branch_id, :inserted_at])
    create index(:orders, [:client_id, :inserted_at], where: "client_id IS NOT NULL")
    create index(:order_items, [:order_id, :product_id])

    flush()

    backfill_product_slugs()

    execute("""
    UPDATE order_items AS oi
    SET category_id = p.category_id, category_name = c.name
    FROM products AS p
    LEFT JOIN categories AS c ON c.id = p.category_id
    WHERE p.id = oi.product_id AND oi.category_id IS NULL
    """)

    create unique_index(:products, [:slug])
  end

  def down do
    drop index(:products, [:slug])
    drop index(:order_items, [:order_id, :product_id])
    drop index(:orders, [:client_id, :inserted_at])
    drop index(:orders, [:branch_id, :inserted_at])

    alter table(:order_items) do
      remove :category_name
      remove :category_id
    end

    drop index(:stocks, [:product_id])

    alter table(:stocks) do
      remove :product_id
    end

    alter table(:products) do
      remove :slug
    end
  end

  defp backfill_product_slugs do
    products =
      repo().all(
        from(p in "products",
          select: %{id: type(p.id, :binary_id), name: p.name},
          order_by: [asc: p.inserted_at]
        )
      )

    Enum.reduce(products, MapSet.new(), fn %{id: id, name: name}, taken ->
      base = Delivest.Slug.slugify(name) || "product"
      slug = Delivest.Slug.unique(base, &MapSet.member?(taken, &1))

      repo().update_all(
        from(p in "products", where: p.id == type(^id, :binary_id)),
        set: [slug: slug]
      )

      MapSet.put(taken, slug)
    end)
  end
end
