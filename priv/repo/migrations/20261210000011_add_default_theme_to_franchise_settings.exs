defmodule Delivest.Repo.Migrations.AddDefaultThemeToFranchiseSettings do
  use Ecto.Migration

  def change do
    alter table(:franchise_settings) do
      add :default_theme, :string, default: "light", null: false
    end
  end
end
