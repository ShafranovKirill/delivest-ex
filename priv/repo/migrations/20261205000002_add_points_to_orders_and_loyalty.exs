defmodule Delivest.Repo.Migrations.AddPointsToOrdersAndLoyalty do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :points_spent, :integer, null: false, default: 0
    end

    drop unique_index(:loyalty_entries, [:kind, :order_id],
           name: :loyalty_entries_order_kind_index
         )

    create unique_index(:loyalty_entries, [:kind, :order_id],
             where:
               "order_id is not null and kind in ('accrual', 'accrual_reversal', 'redeem', 'refund')",
             name: :loyalty_entries_order_kind_index
           )
  end
end
