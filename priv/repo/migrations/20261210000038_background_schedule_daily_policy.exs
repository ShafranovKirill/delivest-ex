defmodule Delivest.Repo.Migrations.BackgroundScheduleDailyPolicy do
  use Ecto.Migration

  def change do
    alter table(:background_schedules) do
      add :manual_requested, :boolean, null: false, default: false
      add :daily_date, :date
    end
  end
end
