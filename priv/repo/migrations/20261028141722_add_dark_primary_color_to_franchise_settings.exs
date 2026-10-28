defmodule Delivest.Repo.Migrations.AddDarkPrimaryColorToFranchiseSettings do
  use Ecto.Migration

  def change do
    alter table(:franchise_settings) do
      add :dark_primary_color, :string
    end
  end
end
