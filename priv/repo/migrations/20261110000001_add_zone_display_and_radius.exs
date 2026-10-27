defmodule Delivest.Repo.Migrations.AddZoneDisplayAndRadius do
  use Ecto.Migration

  def change do
    alter table(:delivery_settings) do
      add :show_zones, :boolean, null: false, default: false
      add :outside_zones, :boolean, null: false, default: false
    end

    alter table(:delivery_zones) do
      add :radius_km, :float
    end
  end
end
