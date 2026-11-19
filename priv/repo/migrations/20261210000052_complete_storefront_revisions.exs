defmodule Delivest.Repo.Migrations.CompleteStorefrontRevisions do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TRIGGER storefront_settings_branches_insert_delete
    AFTER INSERT OR DELETE ON franchise_settings FOR EACH STATEMENT
    EXECUTE FUNCTION storefront_bump_revision('branches')
    """)

    execute("""
    CREATE TRIGGER storefront_settings_branches_update
    AFTER UPDATE OF timezone, loyalty_per_rubles, loyalty_stars, loyalty_expire_days
    ON franchise_settings FOR EACH STATEMENT
    EXECUTE FUNCTION storefront_bump_revision('branches')
    """)

    execute("""
    CREATE FUNCTION storefront_bump_menu_for_branch(target_branch text) RETURNS void AS $$
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
    CREATE FUNCTION storefront_redemption_menu_revision() RETURNS trigger AS $$
    DECLARE
      previous_branch text;
      current_branch text;
    BEGIN
      IF TG_OP <> 'INSERT' THEN
        SELECT branch_id::text INTO previous_branch FROM orders WHERE id = OLD.order_id;
        PERFORM storefront_bump_menu_for_branch(previous_branch);
      END IF;
      IF TG_OP <> 'DELETE' THEN
        SELECT branch_id::text INTO current_branch FROM orders WHERE id = NEW.order_id;
        IF current_branch IS DISTINCT FROM previous_branch THEN
          PERFORM storefront_bump_menu_for_branch(current_branch);
        END IF;
      END IF;
      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql
    """)

    execute("""
    CREATE TRIGGER storefront_redemption_menu_revision
    AFTER INSERT OR UPDATE OR DELETE ON promo_redemptions FOR EACH ROW
    EXECUTE FUNCTION storefront_redemption_menu_revision()
    """)

    execute("""
    CREATE FUNCTION storefront_order_menu_revision() RETURNS trigger AS $$
    BEGIN
      IF EXISTS (SELECT 1 FROM promo_redemptions WHERE order_id = NEW.id) THEN
        PERFORM storefront_bump_menu_for_branch(NEW.branch_id::text);
        IF OLD.branch_id IS DISTINCT FROM NEW.branch_id THEN
          PERFORM storefront_bump_menu_for_branch(OLD.branch_id::text);
        END IF;
      END IF;
      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql
    """)

    execute("""
    CREATE TRIGGER storefront_order_menu_revision
    AFTER UPDATE OF status, crm, deleted_at, branch_id ON orders FOR EACH ROW
    EXECUTE FUNCTION storefront_order_menu_revision()
    """)

    execute("""
    CREATE FUNCTION storefront_order_menu_delete_revision() RETURNS trigger AS $$
    BEGIN
      IF EXISTS (SELECT 1 FROM promo_redemptions WHERE order_id = OLD.id) THEN
        PERFORM storefront_bump_menu_for_branch(OLD.branch_id::text);
      END IF;
      RETURN OLD;
    END;
    $$ LANGUAGE plpgsql
    """)

    execute("""
    CREATE TRIGGER storefront_order_menu_delete_revision
    BEFORE DELETE ON orders FOR EACH ROW
    EXECUTE FUNCTION storefront_order_menu_delete_revision()
    """)
  end

  def down do
    execute("DROP TRIGGER storefront_order_menu_delete_revision ON orders")
    execute("DROP TRIGGER storefront_order_menu_revision ON orders")
    execute("DROP TRIGGER storefront_redemption_menu_revision ON promo_redemptions")
    execute("DROP FUNCTION storefront_order_menu_delete_revision()")
    execute("DROP FUNCTION storefront_order_menu_revision()")
    execute("DROP FUNCTION storefront_redemption_menu_revision()")
    execute("DROP FUNCTION storefront_bump_menu_for_branch(text)")
    execute("DROP TRIGGER storefront_settings_branches_update ON franchise_settings")
    execute("DROP TRIGGER storefront_settings_branches_insert_delete ON franchise_settings")
  end
end
