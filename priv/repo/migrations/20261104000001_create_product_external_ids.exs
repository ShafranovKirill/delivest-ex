defmodule Delivest.Repo.Migrations.CreateProductExternalIds do
  use Ecto.Migration

  def up do
    create table(:product_external_ids, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :product_id, references(:products, type: :binary_id, on_delete: :delete_all),
        null: false

      add :branch_id, :binary_id, null: false
      add :provider, :string, null: false
      add :external_id, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:product_external_ids, [:product_id, :provider])
    create unique_index(:product_external_ids, [:branch_id, :provider, :external_id])

    execute """
    INSERT INTO product_external_ids (id, product_id, branch_id, provider, external_id, inserted_at, updated_at)
    SELECT DISTINCT ON (r.from_id, p.external_id)
           gen_random_uuid(), p.id, r.from_id, 'frontpad', p.external_id, now(), now()
    FROM products p
    JOIN entity_relations r
      ON r.to_id = p.id AND r.to_entity_type = 'Product' AND r.from_entity_type = 'Branch'
    WHERE p.external_id IS NOT NULL AND p.external_id <> '' AND p.deleted_at IS NULL
    ORDER BY r.from_id, p.external_id, p.updated_at DESC
    """

    alter table(:products) do
      remove :external_id
    end
  end

  def down do
    alter table(:products) do
      add :external_id, :string
    end

    execute """
    UPDATE products p SET external_id = e.external_id
    FROM product_external_ids e
    WHERE e.product_id = p.id AND e.provider = 'frontpad'
    """

    drop table(:product_external_ids)
  end
end
