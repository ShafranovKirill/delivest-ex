defmodule Delivest.Repo.Migrations.CreateProductsBranches do
  use Ecto.Migration

  def change do
    create table(:products_branches, primary_key: false) do
      add :product_id,
          references(:products,
            on_delete: :delete_all,
            type: :binary_id,
            name: :products_branches__product_id__fk
          ),
          primary_key: true

      add :branch_id,
          references(:branches,
            on_delete: :delete_all,
            type: :binary_id,
            name: :products_branches__branch_id__fk
          ),
          primary_key: true

      add :is_active, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:products_branches, [:branch_id, :is_active],
             name: :products_branches__branch_id_is_active__index
           )
  end
end
