defmodule Delivest.Repo.Migrations.EnableExistingOwnCouriers do
  use Ecto.Migration

  def up do
    execute """
    WITH inserted AS (
      INSERT INTO feature_gates
        (feature, scope_key, enabled, generation, inserted_at, updated_at)
      SELECT 'couriers', scope_key, true, 1, now(), now()
      FROM (
        SELECT 'franchise' AS scope_key
        UNION ALL
        SELECT 'branch:' || id::text FROM branches
      ) existing_scopes
      ON CONFLICT (feature, scope_key) DO NOTHING
      RETURNING feature, scope_key, enabled, generation
    )
    INSERT INTO feature_audits
      (feature, scope_key, enabled, generation, actor, inserted_at)
    SELECT feature, scope_key, enabled, generation,
           'migration:enable_existing_own_couriers', now()
    FROM inserted
    """
  end

  def down do
    execute """
    DELETE FROM feature_gates g
    WHERE g.feature = 'couriers' AND g.enabled AND g.generation = 1
      AND EXISTS (
        SELECT 1 FROM feature_audits a
        WHERE a.feature = g.feature AND a.scope_key = g.scope_key
          AND a.actor = 'migration:enable_existing_own_couriers'
      )
      AND NOT EXISTS (
        SELECT 1 FROM feature_audits a
        WHERE a.feature = g.feature AND a.scope_key = g.scope_key
          AND a.actor <> 'migration:enable_existing_own_couriers'
      )
    """

    execute """
    DELETE FROM feature_audits
    WHERE feature = 'couriers' AND actor = 'migration:enable_existing_own_couriers'
    """
  end
end
