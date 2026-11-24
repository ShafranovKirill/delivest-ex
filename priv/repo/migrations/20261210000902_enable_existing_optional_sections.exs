defmodule Delivest.Repo.Migrations.EnableExistingOptionalSections do
  use Ecto.Migration

  def up do
    execute """
    CREATE FUNCTION seed_optional_branch_gates() RETURNS trigger AS $$
    BEGIN
      INSERT INTO feature_gates
        (feature, scope_key, enabled, generation, inserted_at, updated_at)
      SELECT feature, 'branch:' || NEW.id::text, true, 1, now(), now()
      FROM (VALUES ('product_import'), ('event_log'), ('analytics_basic'),
                   ('stocks'), ('promotions'), ('loyalty'), ('kitchen')) AS features(feature)
      ON CONFLICT (feature, scope_key) DO NOTHING;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """

    execute """
    CREATE TRIGGER seed_optional_branch_gates_after_insert
    AFTER INSERT ON branches
    FOR EACH ROW EXECUTE FUNCTION seed_optional_branch_gates()
    """

    execute """
    CREATE TRIGGER storefront_optional_content_revision
    AFTER INSERT OR UPDATE OR DELETE ON feature_gates
    FOR EACH STATEMENT EXECUTE FUNCTION storefront_bump_revision('menu,stories')
    """

    execute """
    WITH inserted AS (
      INSERT INTO feature_gates
        (feature, scope_key, enabled, generation, inserted_at, updated_at)
      SELECT feature, scope_key, true, 1, now(), now()
      FROM (VALUES ('product_import'), ('event_log'), ('analytics_basic'),
                   ('stocks'), ('promotions'), ('loyalty'), ('kitchen')) AS features(feature)
      CROSS JOIN (
        SELECT 'franchise' AS scope_key
        UNION ALL
        SELECT 'branch:' || id::text FROM branches
      ) AS scopes
      ON CONFLICT (feature, scope_key) DO NOTHING
      RETURNING feature, scope_key, enabled, generation
    )
    INSERT INTO feature_audits
      (feature, scope_key, enabled, generation, actor, inserted_at)
    SELECT feature, scope_key, enabled, generation,
           'migration:enable_existing_optional_sections', now()
    FROM inserted
    """
  end

  def down do
    execute "DROP TRIGGER IF EXISTS storefront_optional_content_revision ON feature_gates"
    execute "DROP TRIGGER IF EXISTS seed_optional_branch_gates_after_insert ON branches"
    execute "DROP FUNCTION IF EXISTS seed_optional_branch_gates()"

    execute """
    DELETE FROM feature_gates g
    WHERE g.feature IN ('product_import', 'event_log', 'analytics_basic',
                        'stocks', 'promotions', 'loyalty', 'kitchen')
      AND g.enabled AND g.generation = 1
      AND EXISTS (
        SELECT 1 FROM feature_audits a
        WHERE a.feature = g.feature AND a.scope_key = g.scope_key
          AND a.actor = 'migration:enable_existing_optional_sections'
      )
      AND NOT EXISTS (
        SELECT 1 FROM feature_audits a
        WHERE a.feature = g.feature AND a.scope_key = g.scope_key
          AND a.actor <> 'migration:enable_existing_optional_sections'
      )
    """

    execute """
    DELETE FROM feature_audits
    WHERE feature IN ('product_import', 'event_log', 'analytics_basic',
                      'stocks', 'promotions', 'loyalty', 'kitchen')
      AND actor = 'migration:enable_existing_optional_sections'
    """
  end
end
