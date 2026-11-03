defmodule Delivest.Repo.Migrations.AddManualRatingToBranchInfo do
  use Ecto.Migration

  def change do
    alter table(:branch_info) do
      add :manual_rating, :float
    end

    create constraint(:branch_info, :manual_rating_range,
             check: "manual_rating IS NULL OR manual_rating BETWEEN 1 AND 5"
           )
  end
end
