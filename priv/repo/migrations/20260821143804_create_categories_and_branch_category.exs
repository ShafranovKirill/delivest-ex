defmodule Delivest.Repo.Migrations.CreateCategoriesAndBranchCategory do
  use Ecto.Migration

  def change do
    create table(:categories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false

      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create table(:categories_branches, primary_key: false) do
      add :category_id,
          references(:categories,
            on_delete: :delete_all,
            type: :binary_id,
            name: :categories_branches__category_id__fk
          ),
          primary_key: true

      add :branch_id,
          references(:branches,
            on_delete: :delete_all,
            type: :binary_id,
            name: :categories_branches__branch_id__fk
          ),
          primary_key: true

      add :order, :float, null: false

      timestamps()
    end

    create index(:categories_branches, [:branch_id, :order],
             name: :categories_branches__branch_id_order__index
           )

    create index(:categories_branches, [:category_id],
             name: :categories_branches__category_id__index
           )
  end
end
