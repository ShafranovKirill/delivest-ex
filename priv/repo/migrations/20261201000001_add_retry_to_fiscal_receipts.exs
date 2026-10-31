defmodule Delivest.Repo.Migrations.AddRetryToFiscalReceipts do
  use Ecto.Migration

  def change do
    alter table(:fiscal_receipts) do
      add :external_id, :string
      add :retries, :integer, null: false, default: 0
    end

    create index(:fiscal_receipts, [:external_id], where: "external_id IS NOT NULL")
  end
end
