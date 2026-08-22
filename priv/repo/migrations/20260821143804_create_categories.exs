defmodule Delivest.Repo.Migrations.CreateCategories do
  use Ecto.Migration

  def change do
    create table(:categories, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :branch_id,
          references(:branches,
            on_delete: :delete_all,
            type: :binary_id,
            name: :categories__branch_id__fk
          ),
          null: false

      add :name, :string, null: false
      add :order, :float, null: false
      add :is_active, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:categories, [:branch_id, :order], name: :categories__branch_id_order__index)
  end
end
