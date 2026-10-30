defmodule Delivest.Repo.Migrations.AddSpecialHoursToBranchInfo do
  use Ecto.Migration

  def change do
    alter table(:branch_info) do
      add :special_hours, :map, default: %{}, null: false
    end
  end
end
