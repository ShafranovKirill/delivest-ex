defmodule Delivest.Repo.Migrations.LinkFiscalReceiptsToPaymentRefunds do
  use Ecto.Migration

  def up do
    alter table(:fiscal_receipts) do
      add :payment_refund_id, references(:order_refunds, type: :binary_id)
    end

    create unique_index(:fiscal_receipts, [:payment_refund_id], where: "status <> 'fail'")

    drop index(:fiscal_receipts, [:order_id, :kind, :stage], name: :fiscal_receipts_one_per_order)

    create unique_index(:fiscal_receipts, [:order_id, :kind, :stage],
             name: :fiscal_receipts_one_per_order,
             where: "status <> 'fail' AND payment_refund_id IS NULL"
           )
  end

  def down do
    drop index(:fiscal_receipts, [:order_id, :kind, :stage], name: :fiscal_receipts_one_per_order)

    create unique_index(:fiscal_receipts, [:order_id, :kind, :stage],
             name: :fiscal_receipts_one_per_order,
             where: "status <> 'fail'"
           )

    drop index(:fiscal_receipts, [:payment_refund_id])

    alter table(:fiscal_receipts) do
      remove :payment_refund_id
    end
  end
end
