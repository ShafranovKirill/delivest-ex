defmodule Delivest.Repo.Migrations.AddLoyaltyEntryCycles do
  use Ecto.Migration

  def up do
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
  end
end
