defmodule Delivest.Repo.Migrations.CreateDeliveries do
  use Ecto.Migration

  def up do
    create table(:deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :order_id, references(:orders, type: :binary_id, on_delete: :delete_all), null: false
      add :branch_id, references(:branches, type: :binary_id, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :status, :string, null: false
      add :courier_id, references(:staff, type: :binary_id, on_delete: :nilify_all)
      add :assigned_by_id, references(:staff, type: :binary_id, on_delete: :nilify_all)
      add :close_reason, :string
      add :external_id, :string
      add :details, :map, default: %{}, null: false
      add :assigned_at, :utc_datetime_usec
      add :picked_up_at, :utc_datetime_usec
      add :closed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:deliveries, [:order_id],
             where: "status IN ('searching', 'assigned', 'picked_up')",
             name: :deliveries_active_order_index
           )

    create index(:deliveries, [:order_id, :inserted_at])
    create index(:deliveries, [:branch_id, :status])
    create index(:deliveries, [:courier_id, :status])

    alter table(:branch_info) do
      add :couriers, :map, default: %{}, null: false
    end

    execute("""
    UPDATE roles
    SET permissions = (
      SELECT jsonb_agg(DISTINCT permission)
      FROM jsonb_array_elements_text(permissions || '["orders.deliver"]'::jsonb) permission
    )
    WHERE name = 'Управляющий'
    """)
  end

  def down do
    alter table(:branch_info) do
      remove :couriers
    end

    drop table(:deliveries)
  end
end
