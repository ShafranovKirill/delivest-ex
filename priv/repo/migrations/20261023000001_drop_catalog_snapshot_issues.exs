defmodule Delivest.Repo.Migrations.DropCatalogSnapshotIssues do
  use Ecto.Migration

  def change do
    alter table(:crm_catalog_snapshots) do
      remove :issues, :map, null: false, default: fragment("'[]'::jsonb")
    end
  end
end
