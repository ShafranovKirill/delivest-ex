defmodule Delivest.Repo.Migrations.CreateModifiers do
  use Ecto.Migration

  def change do
    create table(:modifier_groups, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :min, :integer, null: false, default: 0
      add :max, :integer, null: false, default: 1
      add :position, :integer, null: false, default: 0
      add :is_active, :boolean, null: false, default: true
      add :is_size, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create table(:modifiers, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :group_id, references(:modifier_groups, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :price, :integer, null: false, default: 0
      add :max_quantity, :integer, null: false, default: 1
      add :is_default, :boolean, null: false, default: false
      add :weight, :integer
      add :position, :integer, null: false, default: 0
      add :is_active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:modifiers, [:group_id])

    create table(:product_modifier_groups, primary_key: false) do
      add :product_id, references(:products, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :group_id, references(:modifier_groups, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :position, :integer, null: false, default: 0
    end

    create index(:product_modifier_groups, [:group_id])

    create table(:modifier_stops, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :modifier_id, references(:modifiers, type: :binary_id, on_delete: :delete_all),
        null: false

      add :branch_id, :binary_id, null: false
      add :until, :utc_datetime
      add :staff_id, :binary_id

      timestamps(type: :utc_datetime)
    end

    create unique_index(:modifier_stops, [:modifier_id, :branch_id])

    create table(:order_item_modifiers, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :order_item_id, references(:order_items, type: :binary_id, on_delete: :delete_all),
        null: false

      add :modifier_id, :binary_id
      add :group_name, :string
      add :name, :string, null: false
      add :price, :integer, null: false, default: 0
      add :quantity, :integer, null: false, default: 1
    end

    create index(:order_item_modifiers, [:order_item_id])

    alter table(:cart_items) do
      add :modifiers, :map, null: false, default: fragment("'[]'::jsonb")
      add :modifier_key, :string, null: false, default: ""
    end

    drop_if_exists unique_index(:cart_items, [:cart_id, :product_id])
    create unique_index(:cart_items, [:cart_id, :product_id, :modifier_key])
  end
end
