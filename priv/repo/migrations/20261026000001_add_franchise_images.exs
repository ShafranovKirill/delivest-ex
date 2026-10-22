defmodule Delivest.Repo.Migrations.AddFranchiseImages do
  use Ecto.Migration

  def change do
    alter table(:franchise_settings) do
      add :icon_key, :string
      add :share_image_key, :string
    end
  end
end
