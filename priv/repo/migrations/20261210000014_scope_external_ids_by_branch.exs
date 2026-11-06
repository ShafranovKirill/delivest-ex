defmodule Delivest.Repo.Migrations.ScopeExternalIdsByBranch do
  use Ecto.Migration

  def up do
    create unique_index(:external_ids, [:entity_type, :entity_id, :branch_id, :provider],
             name: :external_ids_entity_branch_provider_index
           )

    drop_if_exists index(:external_ids, [:entity_type, :entity_id, :provider],
                     name: :external_ids_entity_type_entity_id_provider_index
                   )
  end

  def down do
    execute """
    DO $$ BEGIN
      IF EXISTS (
        SELECT 1 FROM external_ids
        GROUP BY entity_type, entity_id, provider HAVING count(*) > 1
      ) THEN
        RAISE EXCEPTION 'Cannot roll back branch-scoped external IDs: cross-branch conflicts exist';
      END IF;
    END $$;
    """

    create unique_index(:external_ids, [:entity_type, :entity_id, :provider],
             name: :external_ids_entity_type_entity_id_provider_index
           )

    drop_if_exists index(:external_ids, [:entity_type, :entity_id, :branch_id, :provider],
                     name: :external_ids_entity_branch_provider_index
                   )
  end
end
