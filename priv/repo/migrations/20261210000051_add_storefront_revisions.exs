defmodule Delivest.Repo.Migrations.AddStorefrontRevisions do
  use Ecto.Migration

  @global %{
    "franchise_settings" => ["franchise"],
    "legal_documents" => ["franchise"],
    "franchise_ratings" => ["franchise"],
    "dadata_settings" => ["franchise"],
    "zvonok_settings" => ["franchise"],
    "branches" => ["branches"],
    "branch_info" => ["branches"],
    "delivery_settings" => ["branches"],
    "yookassa_settings" => ["branches"],
    "integration_health" => ["branches"],
    "feature_gates" => ["branches", "advertising"],
    "yandex_ads_settings" => ["advertising"],
    "categories" => ["menu"],
    "products" => ["menu", "stories"],
    "product_tags" => ["menu"],
    "modifier_groups" => ["menu"],
    "modifiers" => ["menu"],
    "product_modifier_groups" => ["menu"],
    "popular_products" => ["menu"],
    "entity_relations" => ["menu", "stories"],
    "stocks" => ["stories"],
    "media_files" => ["franchise", "menu", "stories"]
  }

  @scoped %{
    "branches" => {"id", ["menu", "stories", "advertising"]},
    "product_stops" => {"branch_id", ["menu"]},
    "modifier_stops" => {"branch_id", ["menu"]},
    "promotions" => {"branch_id", ["menu"]},
    "popular_settings" => {"branch_id", ["menu"]}
  }

  def up do
    execute("""
    CREATE TABLE storefront_revisions (
      section text NOT NULL,
      scope text NOT NULL DEFAULT '*',
      revision bigint NOT NULL DEFAULT 0,
      PRIMARY KEY (section, scope)
    )
    """)

    execute("""
    CREATE TABLE storefront_epoch (epoch text PRIMARY KEY)
    """)

    execute(
      "INSERT INTO storefront_epoch(epoch) VALUES (md5(random()::text || clock_timestamp()::text))"
    )

    execute("""
    CREATE FUNCTION storefront_bump_revision() RETURNS trigger AS $$
    DECLARE
      target_scope text;
      target_section text;
      row_data jsonb;
    BEGIN
      IF TG_NARGS > 1 THEN
        row_data := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
        target_scope := COALESCE(row_data ->> TG_ARGV[1], '*');
      ELSE
        target_scope := '*';
      END IF;

      FOREACH target_section IN ARRAY string_to_array(TG_ARGV[0], ',') LOOP
        INSERT INTO storefront_revisions(section, scope, revision)
          VALUES(target_section, target_scope, 1)
          ON CONFLICT (section, scope)
          DO UPDATE SET revision = storefront_revisions.revision + 1;
        PERFORM pg_notify('storefront_revision', target_section || '|' || target_scope);
        IF TG_NARGS > 1 AND TG_OP = 'UPDATE' AND
           (to_jsonb(OLD) ->> TG_ARGV[1]) IS DISTINCT FROM target_scope THEN
          INSERT INTO storefront_revisions(section, scope, revision)
            VALUES(target_section, COALESCE(to_jsonb(OLD) ->> TG_ARGV[1], '*'), 1)
            ON CONFLICT (section, scope)
            DO UPDATE SET revision = storefront_revisions.revision + 1;
          PERFORM pg_notify('storefront_revision', target_section || '|' || COALESCE(to_jsonb(OLD) ->> TG_ARGV[1], '*'));
        END IF;
      END LOOP;
      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql
    """)

    for {table, sections} <- @global do
      events =
        if table == "branches",
          do: "INSERT OR DELETE OR TRUNCATE",
          else: "INSERT OR UPDATE OR DELETE OR TRUNCATE"

      execute("""
      CREATE TRIGGER storefront_global_revision AFTER #{events}
      ON #{table} FOR EACH STATEMENT
      EXECUTE FUNCTION storefront_bump_revision('#{Enum.join(sections, ",")}')
      """)

      if table == "branches" do
        execute("""
        CREATE TRIGGER storefront_branch_public_update AFTER UPDATE OF name, slug, is_active, deleted_at
        ON branches FOR EACH STATEMENT
        EXECUTE FUNCTION storefront_bump_revision('branches')
        """)
      end
    end

    for {table, {column, sections}} <- @scoped do
      events = if table == "branches", do: "INSERT OR DELETE", else: "INSERT OR UPDATE OR DELETE"

      execute("""
      CREATE TRIGGER storefront_scoped_revision AFTER #{events}
      ON #{table} FOR EACH ROW
      EXECUTE FUNCTION storefront_bump_revision('#{Enum.join(sections, ",")}', '#{column}')
      """)

      if table == "branches" do
        execute("""
        CREATE TRIGGER storefront_branch_scoped_public_update AFTER UPDATE OF is_active, deleted_at, slug
        ON branches FOR EACH ROW
        EXECUTE FUNCTION storefront_bump_revision('#{Enum.join(sections, ",")}', '#{column}')
        """)
      end

      execute("""
      CREATE TRIGGER storefront_truncate_revision AFTER TRUNCATE
      ON #{table} FOR EACH STATEMENT
      EXECUTE FUNCTION storefront_bump_revision('#{Enum.join(sections, ",")}')
      """)
    end
  end

  def down do
    for {table, _} <- @scoped,
        do:
          (
            execute("DROP TRIGGER IF EXISTS storefront_scoped_revision ON #{table}")
            execute("DROP TRIGGER IF EXISTS storefront_truncate_revision ON #{table}")
          )

    execute("DROP TRIGGER IF EXISTS storefront_branch_scoped_public_update ON branches")

    for {table, _} <- @global,
        do: execute("DROP TRIGGER IF EXISTS storefront_global_revision ON #{table}")

    execute("DROP TRIGGER IF EXISTS storefront_branch_public_update ON branches")

    execute("DROP FUNCTION storefront_bump_revision()")
    execute("DROP TABLE storefront_epoch")
    execute("DROP TABLE storefront_revisions")
  end
end
