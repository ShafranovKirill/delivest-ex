defmodule Delivest.Repo.Migrations.AddOrderCutlerySetting do
  use Ecto.Migration

  def change do
    alter table(:franchise_settings) do
      add :cutlery_enabled, :boolean, default: false, null: false
    end
  end
end
