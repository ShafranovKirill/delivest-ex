defmodule Delivest.Repo.Migrations.AddOrderTiming do
  use Ecto.Migration

  def change do
    alter table(:branch_info) do
      add :timing, :map
    end

    alter table(:orders) do
      add :estimated_ready_at, :utc_datetime
      add :estimated_delivery_at, :utc_datetime
    end
  end
end
