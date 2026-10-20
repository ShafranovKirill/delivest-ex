defmodule Delivest.Repo.Migrations.CreatePromotions do
  use Ecto.Migration

  def change do
    create table(:promotions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :branch_id, references(:branches, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text
      add :kind, :string, null: false
      add :rules, :text, null: false
      add :enabled, :boolean, null: false, default: true
      add :combinable, :boolean, null: false, default: false
      add :priority, :integer, null: false, default: 0
      add :starts_at, :utc_datetime
      add :ends_at, :utc_datetime
      add :usage_limit, :integer
      add :per_client_limit, :integer
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:promotions, [:branch_id])

    create table(:promo_codes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :promotion_id, references(:promotions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :branch_id, references(:branches, type: :binary_id, on_delete: :delete_all), null: false
      add :client_id, references(:clients, type: :binary_id, on_delete: :delete_all)
      add :code, :string, null: false
      add :usage_limit, :integer
      add :issued_by_id, :binary_id

      timestamps(type: :utc_datetime)
    end

    create unique_index(:promo_codes, [:branch_id, "upper(code)"],
             name: :promo_codes_branch_id_code_index
           )

    create index(:promo_codes, [:promotion_id])
    create index(:promo_codes, [:client_id])

    create table(:promo_redemptions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :promotion_id, references(:promotions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :promo_code_id, references(:promo_codes, type: :binary_id, on_delete: :nilify_all)
      add :order_id, references(:orders, type: :binary_id, on_delete: :delete_all), null: false
      add :client_id, references(:clients, type: :binary_id, on_delete: :nilify_all)
      add :discount, :integer, null: false, default: 0

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:promo_redemptions, [:order_id, :promotion_id])
    create index(:promo_redemptions, [:promotion_id])
    create index(:promo_redemptions, [:promo_code_id])
    create index(:promo_redemptions, [:client_id])

    alter table(:carts) do
      add :promo_code, :string
      add :fulfillment_type, :string
      add :client_id, :binary_id
    end

    alter table(:orders) do
      add :subtotal_amount, :integer
      add :discount_amount, :integer, null: false, default: 0
      add :promotions, :map, null: false, default: fragment("'[]'::jsonb")
    end

    alter table(:order_items) do
      add :base_price, :integer
      add :gift, :boolean, null: false, default: false
    end
  end
end
