defmodule Delivest.Repo.Migrations.AddSettlementToPayments do
  use Ecto.Migration

  def up do
    alter table(:order_payments) do
      add :settlement_id, references(:courier_settlements, type: :uuid, on_delete: :nilify_all)
    end

    create index(:order_payments, [:settlement_id])

    execute """
    UPDATE order_payments p SET collected_by_id = d.courier_id
    FROM deliveries d
    WHERE d.order_id = p.order_id AND d.provider = 'staff' AND d.status = 'delivered'
      AND p.method IN ('cash', 'card') AND p.status = 'paid'
    """

    execute """
    UPDATE order_payments p SET settlement_id = (
      SELECT s.id FROM courier_settlements s
      JOIN deliveries d ON d.courier_id = s.courier_id AND d.order_id = p.order_id
      WHERE s.branch_id = p.branch_id AND d.closed_at <= s.until
      ORDER BY s.until ASC LIMIT 1
    )
    WHERE p.method IN ('cash', 'card') AND p.status = 'paid' AND p.collected_by_id IS NOT NULL
    """
  end

  def down do
    alter table(:order_payments) do
      remove :settlement_id
    end
  end
end
