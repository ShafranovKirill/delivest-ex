defmodule Delivest.Repo.Migrations.IntegrateRecoveryLedgers do
  use Ecto.Migration

  def up do
    alter table(:event_deliveries) do
      add :last_error, :text
    end

    drop constraint(:event_deliveries, :event_deliveries_status_valid)

    create constraint(:event_deliveries, :event_deliveries_status_valid,
             check: "status IN ('pending', 'delivered', 'resolved', 'blocked')"
           )

    alter table(:loyalty_entries) do
      add :cycle, :integer, null: false, default: 0
    end

    drop index(:loyalty_entries, [:kind, :order_id], name: :loyalty_entries_order_kind_index)

    create unique_index(:loyalty_entries, [:kind, :order_id],
             name: :loyalty_entries_order_single_index,
             where: "order_id IS NOT NULL AND kind IN ('redeem', 'refund')"
           )

    create unique_index(:loyalty_entries, [:kind, :order_id, :cycle],
             name: :loyalty_entries_order_cycle_index,
             where: "order_id IS NOT NULL AND kind IN ('accrual', 'accrual_reversal')"
           )
  end

  def down do
    drop index(:loyalty_entries, [:kind, :order_id, :cycle],
           name: :loyalty_entries_order_cycle_index
         )

    drop index(:loyalty_entries, [:kind, :order_id], name: :loyalty_entries_order_single_index)

    create unique_index(:loyalty_entries, [:kind, :order_id],
             name: :loyalty_entries_order_kind_index,
             where:
               "order_id IS NOT NULL AND kind IN ('accrual', 'accrual_reversal', 'redeem', 'refund')"
           )

    alter table(:loyalty_entries) do
      remove :cycle
    end

    execute "UPDATE event_deliveries SET status = 'pending' WHERE status = 'blocked'"
    drop constraint(:event_deliveries, :event_deliveries_status_valid)

    create constraint(:event_deliveries, :event_deliveries_status_valid,
             check: "status IN ('pending', 'delivered', 'resolved')"
           )

    alter table(:event_deliveries) do
      remove :last_error
    end
  end
end
