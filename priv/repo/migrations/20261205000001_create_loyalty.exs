defmodule Delivest.Repo.Migrations.CreateLoyalty do
  use Ecto.Migration

  def change do
    create table(:loyalty_entries, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :client_id, references(:clients, type: :uuid, on_delete: :delete_all), null: false
      add :branch_id, :uuid
      add :order_id, references(:orders, type: :uuid, on_delete: :nilify_all)
      add :kind, :string, null: false
      add :amount, :integer, null: false
      add :remaining, :integer, null: false, default: 0
      add :expires_at, :utc_datetime
      add :reason, :string
      add :staff_id, references(:staff, type: :uuid, on_delete: :nilify_all)

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:loyalty_entries, [:client_id, :inserted_at])
    create index(:loyalty_entries, [:branch_id, :kind])

    create unique_index(:loyalty_entries, [:kind, :order_id],
             where: "order_id is not null and kind in ('accrual', 'accrual_reversal')",
             name: :loyalty_entries_order_kind_index
           )

    create table(:loyalty_accounts, primary_key: false) do
      add :client_id, references(:clients, type: :uuid, on_delete: :delete_all), primary_key: true

      add :balance, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    alter table(:branch_info) do
      add :loyalty, :map, default: %{}, null: false
    end
  end
end
