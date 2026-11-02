defmodule Delivest.Repo.Migrations.AddFulfillmentToBranchInfo do
  use Ecto.Migration

  def change do
    alter table(:branch_info) do
      add :fulfillment, :map, null: false, default: %{}
    end
  end
end
