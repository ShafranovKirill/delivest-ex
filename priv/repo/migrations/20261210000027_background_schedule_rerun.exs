defmodule Delivest.Repo.Migrations.BackgroundScheduleRerun do
  use Ecto.Migration

  def change do
    alter table(:background_schedules) do
      add :rerun_requested, :boolean, null: false, default: false
    end
  end
end
