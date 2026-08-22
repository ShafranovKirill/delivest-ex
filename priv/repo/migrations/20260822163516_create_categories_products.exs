defmodule Delivest.Repo.Migrations.CreateCategoriesProducts do
  use Ecto.Migration

  def change do
    create table(:categories_products, primary_key: false) do
      add :category_id,
          references(:categories,
            on_delete: :delete_all,
            type: :binary_id,
            name: :categories_products__category_id__fk
          ),
          primary_key: true

      add :product_id,
          references(:products,
            on_delete: :delete_all,
            type: :binary_id,
            name: :categories_products__product_id__fk
          ),
          primary_key: true

      timestamps(type: :utc_datetime)
    end

    create index(:categories_products, [:category_id],
             name: :categories_products__category_id__index
           )

    create index(:categories_products, [:product_id],
             name: :categories_products__product_id__index
           )
  end
end
