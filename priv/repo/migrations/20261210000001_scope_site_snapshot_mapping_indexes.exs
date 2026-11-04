defmodule Delivest.Repo.Migrations.ScopeSiteSnapshotMappingIndexes do
  use Ecto.Migration

  def up do
    drop_if_exists unique_index(
                     :site_snapshot_mappings,
                     [:target_branch_id, :entity_type, :target_id],
                     name: :site_snapshot_target_unique
                   )

    create unique_index(
             :site_snapshot_mappings,
             [:source_installation_id, :target_branch_id, :entity_type, :target_id],
             name: :site_snapshot_target_unique
           )

    create unique_index(
             :site_snapshot_mappings,
             [:source_installation_id, :entity_type, :source_id],
             where: "entity_type = 'branches'",
             name: :site_snapshot_branch_source_unique
           )
  end

  def down do
    drop_if_exists unique_index(
                     :site_snapshot_mappings,
                     [:source_installation_id, :entity_type, :source_id],
                     name: :site_snapshot_branch_source_unique
                   )

    drop_if_exists unique_index(
                     :site_snapshot_mappings,
                     [:source_installation_id, :target_branch_id, :entity_type, :target_id],
                     name: :site_snapshot_target_unique
                   )

    create unique_index(
             :site_snapshot_mappings,
             [:target_branch_id, :entity_type, :target_id],
             name: :site_snapshot_target_unique
           )
  end
end
