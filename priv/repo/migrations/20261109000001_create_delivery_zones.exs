defmodule Delivest.Repo.Migrations.CreateDeliveryZones do
  use Ecto.Migration

  def change do
    create table(:delivery_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :branch_id, references(:branches, type: :binary_id, on_delete: :delete_all), null: false
      add :mode, :string, null: false, default: "flat"
      add :thresholds, :map, null: false, default: fragment("'[]'::jsonb")

      timestamps(type: :utc_datetime)
    end

    create unique_index(:delivery_settings, [:branch_id])

    create table(:delivery_zones, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :branch_id, references(:branches, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :color, :string, null: false
      add :enabled, :boolean, null: false, default: true
      add :position, :integer, null: false, default: 0
      add :polygon, :map, null: false
      add :geometry_version, :integer, null: false, default: 1
      add :delivery_minutes, :integer
      add :thresholds, :map, null: false, default: fragment("'[]'::jsonb")
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:delivery_zones, [:branch_id])
  end
end
