defmodule Delivest.Repo.Migrations.AddWorkingHoursToBranchInfo do
  use Ecto.Migration

  def change do
    alter table(:branch_info) do
      add :working_hours, :map, default: %{}
    end
  end
end
