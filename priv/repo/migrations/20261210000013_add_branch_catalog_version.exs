defmodule Delivest.Repo.Migrations.AddBranchCatalogVersion do
  use Ecto.Migration

  def change do
    alter table(:branches) do
      add :catalog_version, :bigint, null: false, default: 0
    end
  end
end
