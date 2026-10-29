defmodule Delivest.Repo.Migrations.CreateOrderPayments do
  use Ecto.Migration

  def change do
    create table(:order_payments, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :order_id, references(:orders, type: :uuid, on_delete: :delete_all), null: false
      add :branch_id, :uuid, null: false
      add :method, :string, null: false
      add :amount, :integer, null: false
      add :status, :string, null: false
      add :provider, :string
      add :external_id, :string
      add :collected_by_id, references(:staff, type: :uuid, on_delete: :nilify_all)
      add :cash_given, :integer
      add :paid_at, :utc_datetime
      add :fiscalized_by, :string
      add :details, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:order_payments, [:order_id])
    create index(:order_payments, [:collected_by_id, :paid_at])
    create unique_index(:order_payments, [:provider, :external_id])

    create table(:order_refunds, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :payment_id, references(:order_payments, type: :uuid, on_delete: :delete_all),
        null: false

      add :order_id, references(:orders, type: :uuid, on_delete: :delete_all), null: false
      add :amount, :integer, null: false
      add :reason, :string
      add :status, :string, null: false
      add :provider, :string
      add :external_id, :string
      add :refunded_by_id, references(:staff, type: :uuid, on_delete: :nilify_all)
      add :refunded_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:order_refunds, [:payment_id])
    create index(:order_refunds, [:order_id])
    create unique_index(:order_refunds, [:provider, :external_id])
  end
end
