defmodule Delivest.Repo.Migrations.AddFranchiseLogos do
  use Ecto.Migration

  def change do
    alter table(:franchise_settings) do
      add :logo_key, :string
      add :logo_dark_key, :string
    end
  end
end
