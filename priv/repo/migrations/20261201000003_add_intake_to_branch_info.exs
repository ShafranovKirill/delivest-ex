defmodule Delivest.Repo.Migrations.AddIntakeToBranchInfo do
  use Ecto.Migration

  def change do
    alter table(:branch_info) do
      add :intake, :map, default: %{}, null: false
    end
  end
end
