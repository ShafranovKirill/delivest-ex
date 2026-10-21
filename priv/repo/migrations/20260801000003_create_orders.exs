defmodule Delivest.Repo.Migrations.CreateOrders do
  use Ecto.Migration

  def change do
    create table(:carts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :session_id, :string
      add :staff_id, :binary_id
      add :client_id, :binary_id
      add :branch_id, :binary_id
      add :fulfillment_type, :string
      add :promo_code, :string
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:carts, [:session_id], where: "session_id IS NOT NULL")
    create index(:carts, [:staff_id], where: "staff_id IS NOT NULL")
    create index(:carts, [:branch_id])

    create table(:cart_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :cart_id, references(:carts, type: :binary_id, on_delete: :delete_all), null: false
      add :product_id, :binary_id, null: false
      add :quantity, :integer, null: false, default: 1

      timestamps(type: :utc_datetime)
    end

    create index(:cart_items, [:cart_id])
    create unique_index(:cart_items, [:cart_id, :product_id])

    execute(
      "CREATE SEQUENCE order_number_seq MINVALUE 0 MAXVALUE 25999 CYCLE START WITH 0",
      "DROP SEQUENCE order_number_seq"
    )

    create table(:orders, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :number, :string, null: false
      add :branch_id, :binary_id, null: false
      add :cart_id, :binary_id, null: false
      add :staff_id, :binary_id
      add :client_id, :binary_id
      add :session_id, :string
      add :status, :string, null: false, default: "created"
      add :fulfillment_type, :string, null: false, default: "dine_in"
      add :payment_method, :string, null: false, default: "cash"
      add :subtotal_amount, :integer
      add :discount_amount, :integer, null: false, default: 0
      add :total_amount, :integer, null: false, default: 0
      add :promotions, :map, null: false, default: fragment("'[]'::jsonb")
      add :address, :jsonb, default: "{}"
      add :cook_by, :naive_datetime
      add :comment, :text
      add :crm, :map
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:orders, [:number])
    create index(:orders, [:branch_id])
    create index(:orders, [:branch_id, :inserted_at])
    create index(:orders, [:staff_id], where: "staff_id IS NOT NULL")
    create index(:orders, [:client_id], where: "client_id IS NOT NULL")
    create index(:orders, [:client_id, :inserted_at], where: "client_id IS NOT NULL")
    create index(:orders, [:session_id, :inserted_at])

    create table(:order_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :order_id, references(:orders, type: :binary_id, on_delete: :delete_all), null: false
      add :product_id, :binary_id, null: false
      add :title, :string, null: false
      add :price, :integer, null: false
      add :base_price, :integer
      add :quantity, :integer, null: false, default: 1
      add :gift, :boolean, null: false, default: false
      add :category_id, :binary_id
      add :category_name, :string

      timestamps(type: :utc_datetime)
    end

    create index(:order_items, [:order_id])
    create index(:order_items, [:product_id])
    create index(:order_items, [:order_id, :product_id])
  end
end
