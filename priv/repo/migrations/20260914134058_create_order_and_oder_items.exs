defmodule Delivest.Repo.Migrations.CreateOrderAndOderItems do
  use Ecto.Migration

  def change do
    create table(:orders, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :number, :string, null: false

      add :staff_id, :binary_id
      add :client_id, :binary_id
      add :branch_id, :binary_id, null: false

      add :status, :string, null: false, default: "created"

      # Способ выдачи: dine_in (в ресторане), delivery (доставка), pickup (самовывоз)
      add :fulfillment_type, :string, null: false, default: "dine_in"

      # Способ оплаты: cash (наличные), card_offline (карта курьеру / терминал)
      add :payment_method, :string, null: false, default: "cash"

      add :total_amount, :integer, null: false, default: 0

      add :address, :jsonb, default: "{}"

      add :comment, :text

      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:orders, [:number])
    create index(:orders, [:staff_id], where: "staff_id IS NOT NULL")
    create index(:orders, [:client_id], where: "client_id IS NOT NULL")
    create index(:orders, [:branch_id])
    create index(:orders, [:status])
    create index(:orders, [:fulfillment_type])
    create index(:orders, [:payment_method])

    create table(:order_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :order_id, references(:orders, type: :binary_id, on_delete: :delete_all), null: false
      add :product_id, :binary_id, null: false
      add :price, :integer, null: false
      add :quantity, :integer, null: false, default: 1

      timestamps(type: :utc_datetime)
    end

    create index(:order_items, [:order_id])
    create index(:order_items, [:product_id])
  end
end
