defmodule Delivest.Repo.Migrations.AddStorefrontMaintenance do
  use Ecto.Migration

  def up do
    alter table(:franchise_settings) do
      add :maintenance_enabled, :boolean, default: false, null: false
    end

    alter table(:branch_info) do
      add :maintenance_enabled, :boolean, default: false, null: false
    end

    execute("DROP TRIGGER storefront_settings_branches_update ON franchise_settings")

    execute("""
    CREATE TRIGGER storefront_settings_branches_update
    AFTER UPDATE OF timezone, loyalty_per_rubles, loyalty_stars, loyalty_expire_days, maintenance_enabled
    ON franchise_settings FOR EACH STATEMENT
    EXECUTE FUNCTION storefront_bump_revision('branches')
    """)
  end

  def down do
    execute("DROP TRIGGER storefront_settings_branches_update ON franchise_settings")

    execute("""
    CREATE TRIGGER storefront_settings_branches_update
    AFTER UPDATE OF timezone, loyalty_per_rubles, loyalty_stars, loyalty_expire_days
    ON franchise_settings FOR EACH STATEMENT
    EXECUTE FUNCTION storefront_bump_revision('branches')
    """)

    alter table(:branch_info) do
      remove :maintenance_enabled
    end

    alter table(:franchise_settings) do
      remove :maintenance_enabled
    end
  end
end
