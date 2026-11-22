defmodule Delivest.Repo.Migrations.AddPrintingSettingsToBranchInfo do
  use Ecto.Migration

  def change do
    alter table(:branch_info) do
      add :printing, :map, default: %{}, null: false
    end
  end
end
