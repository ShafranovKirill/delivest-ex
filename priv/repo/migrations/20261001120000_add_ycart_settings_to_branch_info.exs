defmodule Delivest.Repo.Migrations.AddYcartSettingsToBranchInfo do
  use Ecto.Migration

  def change do
    alter table(:branch_info) do
      add :ycart_settings, :map, default: %{enabled: false}
    end
  end
end
