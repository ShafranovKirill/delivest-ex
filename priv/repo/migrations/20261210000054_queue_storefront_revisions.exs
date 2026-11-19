defmodule Delivest.Repo.Migrations.QueueStorefrontRevisions do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE storefront_revision_pending (
      transaction_id xid8 NOT NULL,
      section text NOT NULL,
      scope text NOT NULL,
      delta bigint NOT NULL,
      PRIMARY KEY (transaction_id, section, scope)
    )
    """)

    execute(
      "CREATE INDEX storefront_revision_pending_section_scope ON storefront_revision_pending (section, scope)"
    )

    execute("""
    CREATE FUNCTION storefront_record_revision(target_section text, target_scope text) RETURNS void AS $$
    BEGIN
      INSERT INTO storefront_revision_pending(transaction_id, section, scope, delta)
        VALUES (pg_current_xact_id(), target_section, target_scope, 1)
        ON CONFLICT (transaction_id, section, scope)
        DO UPDATE SET delta = storefront_revision_pending.delta + 1;
      PERFORM pg_notify('storefront_revision', target_section || '|' || target_scope);
    END;
    $$ LANGUAGE plpgsql
    """)

    execute("""
    CREATE OR REPLACE FUNCTION storefront_bump_revision() RETURNS trigger AS $$
    DECLARE
      target_scope text;
      target_section text;
      row_data jsonb;
      old_scope text;
    BEGIN
      IF TG_NARGS > 1 THEN
        row_data := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
        target_scope := COALESCE(row_data ->> TG_ARGV[1], '*');
      ELSE
        target_scope := '*';
      END IF;

      FOREACH target_section IN ARRAY string_to_array(TG_ARGV[0], ',') LOOP
        PERFORM storefront_record_revision(target_section, target_scope);
        IF TG_NARGS > 1 AND TG_OP = 'UPDATE' THEN
          old_scope := COALESCE(to_jsonb(OLD) ->> TG_ARGV[1], '*');
          IF old_scope IS DISTINCT FROM target_scope THEN
            PERFORM storefront_record_revision(target_section, old_scope);
          END IF;
        END IF;
      END LOOP;
      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql
    """)

    execute("""
    CREATE OR REPLACE FUNCTION storefront_bump_menu_for_branch(target_branch text) RETURNS void AS $$
    BEGIN
      IF target_branch IS NOT NULL THEN
        PERFORM storefront_record_revision('menu', target_branch);
      END IF;
    END;
    $$ LANGUAGE plpgsql
    """)
  end

  def down do
    execute("""
    INSERT INTO storefront_revisions(section, scope, revision)
    SELECT section, scope, SUM(delta)
    FROM storefront_revision_pending GROUP BY section, scope
    ON CONFLICT (section, scope)
    DO UPDATE SET revision = storefront_revisions.revision + EXCLUDED.revision
    """)

    execute("""
    CREATE OR REPLACE FUNCTION storefront_bump_menu_for_branch(target_branch text) RETURNS void AS $$
    BEGIN
      IF target_branch IS NOT NULL THEN
        INSERT INTO storefront_revisions(section, scope, revision)
          VALUES('menu', target_branch, 1)
          ON CONFLICT (section, scope)
          DO UPDATE SET revision = storefront_revisions.revision + 1;
        PERFORM pg_notify('storefront_revision', 'menu|' || target_branch);
      END IF;
    END;
    $$ LANGUAGE plpgsql
    """)

    execute("""
    CREATE OR REPLACE FUNCTION storefront_bump_revision() RETURNS trigger AS $$
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

    execute("DROP FUNCTION storefront_record_revision(text, text)")
    execute("DROP INDEX storefront_revision_pending_section_scope")
    execute("DROP TABLE storefront_revision_pending")
  end
end
