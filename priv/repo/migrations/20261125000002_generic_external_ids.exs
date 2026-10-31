defmodule Delivest.Repo.Migrations.GenericExternalIds do
  use Ecto.Migration

  def up do
    drop index(:product_external_ids, [:product_id, :provider])
    drop index(:product_external_ids, [:branch_id, :provider, :external_id])

    execute "ALTER TABLE product_external_ids DROP CONSTRAINT IF EXISTS product_external_ids_product_id_fkey"

    rename table(:product_external_ids), to: table(:external_ids)
    rename table(:external_ids), :product_id, to: :entity_id

    alter table(:external_ids) do
      add :entity_type, :string, null: false, default: "product"
    end

    create unique_index(:external_ids, [:entity_type, :entity_id, :provider])
    create unique_index(:external_ids, [:entity_type, :branch_id, :provider, :external_id])

    execute """
    CREATE FUNCTION drop_product_external_ids() RETURNS trigger AS $$
    BEGIN
      DELETE FROM external_ids WHERE entity_type = 'product' AND entity_id = OLD.id;
      RETURN OLD;
    END $$ LANGUAGE plpgsql
    """

    execute """
    CREATE TRIGGER products_external_ids_cleanup AFTER DELETE ON products
    FOR EACH ROW EXECUTE FUNCTION drop_product_external_ids()
    """
  end

  def down do
    execute "DROP TRIGGER products_external_ids_cleanup ON products"
    execute "DROP FUNCTION drop_product_external_ids()"
    execute "DELETE FROM external_ids WHERE entity_type <> 'product'"
    drop index(:external_ids, [:entity_type, :entity_id, :provider])
    drop index(:external_ids, [:entity_type, :branch_id, :provider, :external_id])

    alter table(:external_ids) do
      remove :entity_type
    end

    rename table(:external_ids), :entity_id, to: :product_id
    rename table(:external_ids), to: table(:product_external_ids)
    create unique_index(:product_external_ids, [:product_id, :provider])
    create unique_index(:product_external_ids, [:branch_id, :provider, :external_id])
  end
end
