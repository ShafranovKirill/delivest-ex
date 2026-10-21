defmodule Delivest.Repo.Migrations.TuneIndexes do
  use Ecto.Migration

  def change do
    create index(:products, [:category_id])
    create index(:orders, [:cart_id])

    create index(:orders, [:branch_id, "(crm->>'external_id')"],
             name: :orders_crm_external_id_index,
             where: "crm IS NOT NULL"
           )

    create index(:orders, [:inserted_at],
             name: :orders_open_inserted_at_index,
             where:
               "status IN ('created', 'preparing', 'ready', 'delivering') AND deleted_at IS NULL"
           )

    drop index(:orders, [:branch_id])
    drop index(:orders, [:client_id], where: "client_id IS NOT NULL")
    drop index(:order_items, [:order_id])
    drop index(:cart_items, [:cart_id])
    drop index(:entity_relations, [:from_entity_type, :from_id])
  end
end
