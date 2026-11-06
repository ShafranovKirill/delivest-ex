defmodule Delivest.Repo.Migrations.AddLoyaltyExpiryDeliveries do
  use Ecto.Migration

  def change do
    alter table(:loyalty_expiry_notifications) do
      add :branch_id, references(:branches, type: :uuid, on_delete: :nilify_all)
      add :stars, :integer
      add :expires_at, :utc_datetime
    end

    create table(:loyalty_expiry_deliveries, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :notification_id,
          references(:loyalty_expiry_notifications, type: :uuid, on_delete: :delete_all),
          null: false

      add :subscription_id, :uuid, null: false
      add :status, :string, null: false, default: "pending"
      add :attempts, :integer, null: false, default: 0
      add :last_error, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:loyalty_expiry_deliveries, [:notification_id, :subscription_id])
    create index(:loyalty_expiry_deliveries, [:status, :updated_at])
  end
end
