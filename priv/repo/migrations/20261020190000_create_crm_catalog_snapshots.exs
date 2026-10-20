defmodule Delivest.Repo.Migrations.CreateCrmCatalogSnapshots do
  use Ecto.Migration

  def change do
    create table(:crm_catalog_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :branch_id, references(:branches, type: :binary_id, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :products, :map, null: false, default: fragment("'[]'::jsonb")
      add :issues, :map, null: false, default: fragment("'[]'::jsonb")
      add :checked_at, :utc_datetime, null: false
    end

    create unique_index(:crm_catalog_snapshots, [:branch_id])
  end
end
