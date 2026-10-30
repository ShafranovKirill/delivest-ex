defmodule Delivest.Repo.Migrations.FiscalReceiptPerOrder do
  use Ecto.Migration

  def up do
    alter table(:fiscal_receipts) do
      add :payment_ids, {:array, :binary_id}, null: false, default: []
    end

    execute "UPDATE fiscal_receipts SET payment_ids = ARRAY[payment_id] WHERE payment_id IS NOT NULL"

    drop index(:fiscal_receipts, [:payment_id, :kind, :stage],
           name: :fiscal_receipts_one_per_payment
         )

    alter table(:fiscal_receipts) do
      remove :payment_id
    end

    execute """
    UPDATE fiscal_receipts SET status = 'fail', error = 'superseded'
    WHERE id IN (
      SELECT id FROM (
        SELECT id, row_number() OVER (PARTITION BY order_id, kind, stage ORDER BY inserted_at) AS n
        FROM fiscal_receipts WHERE status <> 'fail'
      ) ranked WHERE n > 1
    )
    """

    create unique_index(:fiscal_receipts, [:order_id, :kind, :stage],
             where: "status <> 'fail'",
             name: :fiscal_receipts_one_per_order
           )
  end

  def down do
    drop index(:fiscal_receipts, [:order_id, :kind, :stage], name: :fiscal_receipts_one_per_order)

    alter table(:fiscal_receipts) do
      add :payment_id, references(:order_payments, type: :binary_id, on_delete: :nilify_all)
    end

    execute "UPDATE fiscal_receipts SET payment_id = payment_ids[1]"

    alter table(:fiscal_receipts) do
      remove :payment_ids
    end

    create unique_index(:fiscal_receipts, [:payment_id, :kind, :stage],
             where: "status <> 'fail' AND payment_id IS NOT NULL",
             name: :fiscal_receipts_one_per_payment
           )
  end
end
