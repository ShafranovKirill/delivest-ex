defmodule Delivest.Repo.Migrations.CreateYandexEdaBusyModes do
  use Ecto.Migration

  def change do
    create table(:yandex_eda_busy_modes, primary_key: false) do
      add :branch_id, :binary_id, primary_key: true
      add :extra_minutes, :integer, null: false
      add :valid_till, :utc_datetime, null: false
      timestamps(type: :utc_datetime)
    end
  end
end
