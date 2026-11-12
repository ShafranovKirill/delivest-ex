defmodule Delivest.Repo.Migrations.DeliveryAddressModeAndPopularProducts do
  use Ecto.Migration

  def change do
    alter table(:delivery_settings) do
      add :map_address, :boolean, null: false, default: true
      add :operator_address, :boolean, null: false, default: false
    end

    alter table(:orders) do
      add :address_by_operator, :boolean, null: false, default: false
    end

    create table(:popular_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :branch_id, references(:branches, type: :binary_id, on_delete: :delete_all), null: false
      add :mode, :string, null: false, default: "off"
      add :auto_limit, :integer, null: false, default: 6
      timestamps(type: :utc_datetime)
    end

    create unique_index(:popular_settings, [:branch_id])

    create table(:popular_products, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :branch_id, references(:branches, type: :binary_id, on_delete: :delete_all), null: false

      add :product_id, references(:products, type: :binary_id, on_delete: :delete_all),
        null: false

      add :position, :integer, null: false, default: 0
      timestamps(type: :utc_datetime)
    end

    create unique_index(:popular_products, [:branch_id, :product_id])
    create index(:popular_products, [:branch_id, :position])
  end
end
