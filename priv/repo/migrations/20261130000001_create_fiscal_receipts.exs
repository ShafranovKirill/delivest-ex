defmodule Delivest.Repo.Migrations.CreateFiscalReceipts do
  use Ecto.Migration

  def change do
    create table(:fiscal_receipts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :order_id, references(:orders, type: :binary_id, on_delete: :restrict), null: false
      add :branch_id, :binary_id, null: false
      add :payment_id, references(:order_payments, type: :binary_id, on_delete: :nilify_all)
      add :refund_of_id, references(:fiscal_receipts, type: :binary_id, on_delete: :nilify_all)
      add :issued_by_id, references(:staff, type: :binary_id, on_delete: :nilify_all)
      add :kind, :string, null: false
      add :stage, :string, null: false
      add :provider, :string, null: false
      add :uuid, :string
      add :status, :string, null: false, default: "pending"
      add :amount, :integer, null: false
      add :request, :map
      add :payload, :map
      add :error, :text
      add :attempts, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:fiscal_receipts, [:order_id])
    create index(:fiscal_receipts, [:branch_id, :status])

    create unique_index(:fiscal_receipts, [:payment_id, :kind, :stage],
             where: "status <> 'fail' AND payment_id IS NOT NULL",
             name: :fiscal_receipts_one_per_payment
           )

    alter table(:products) do
      add :vat, :string
    end

    alter table(:branch_info) do
      add :fiscal, :map
    end
  end
end
