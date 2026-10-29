defmodule Delivest.Repo.Migrations.AddBoardTokenToBranchInfo do
  use Ecto.Migration

  def change do
    alter table(:branch_info) do
      add :board_token, :string
    end

    create unique_index(:branch_info, [:board_token])
  end
end
