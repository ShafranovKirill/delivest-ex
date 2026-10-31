defmodule Delivest.Repo.Migrations.SnapshotLoyaltyEarnings do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :points_earned, :integer
    end

    alter table(:order_items) do
      add :stars_reward, :integer, default: 0, null: false
    end
  end
end
