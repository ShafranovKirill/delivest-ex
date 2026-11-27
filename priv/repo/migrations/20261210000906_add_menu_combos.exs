defmodule Delivest.Repo.Migrations.AddMenuCombos do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :is_combo, :boolean, null: false, default: false
    end

    alter table(:modifiers) do
      add :component_product_id, references(:products, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:modifiers, [:component_product_id])
  end
end
