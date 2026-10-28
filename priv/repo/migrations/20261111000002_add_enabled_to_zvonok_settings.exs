defmodule Delivest.Repo.Migrations.AddEnabledToZvonokSettings do
  use Ecto.Migration

  def change do
    alter table(:zvonok_settings) do
      add :enabled, :boolean, null: false, default: true
    end
  end
end
