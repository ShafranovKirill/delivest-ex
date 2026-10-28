defmodule Delivest.Repo.Migrations.AddKitchenToBranchInfo do
  use Ecto.Migration

  def change do
    alter table(:branch_info) do
      add :kitchen, :map, default: %{}, null: false
    end
  end
end
