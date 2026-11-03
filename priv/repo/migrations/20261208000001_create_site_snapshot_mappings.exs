defmodule Delivest.Repo.Migrations.CreateSiteSnapshotMappings do
  use Ecto.Migration

  def change do
    create table(:site_snapshot_installation, primary_key: false) do
      add :id, :integer, primary_key: true
      add :installation_id, :uuid, null: false
    end

    create table(:site_snapshot_mappings, primary_key: false) do
      add :source_installation_id, :uuid, null: false

      add :target_branch_id, references(:branches, type: :binary_id, on_delete: :delete_all),
        null: false

      add :entity_type, :string, null: false
      add :source_id, :uuid, null: false
      add :target_id, :uuid, null: false
    end

    create unique_index(
             :site_snapshot_mappings,
             [:source_installation_id, :target_branch_id, :entity_type, :source_id],
             name: :site_snapshot_source_unique
           )

    create unique_index(:site_snapshot_mappings, [:target_branch_id, :entity_type, :target_id],
             name: :site_snapshot_target_unique
           )
  end
end
