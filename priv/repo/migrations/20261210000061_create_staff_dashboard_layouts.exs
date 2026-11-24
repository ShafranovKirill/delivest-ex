defmodule Delivest.Repo.Migrations.CreateStaffDashboardLayouts do
  use Ecto.Migration

  def change do
    create table(:staff_dashboard_layouts, primary_key: false) do
      add :staff_id, references(:staff, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :layout, :map, null: false
      timestamps(type: :utc_datetime)
    end
  end
end
