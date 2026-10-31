defmodule Delivest.Repo.Migrations.AddStarsToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :stars_price, :integer
      add :stars_reward, :integer
    end

    alter table(:order_items) do
      add :stars_spent, :integer, null: false, default: 0
    end
  end
end
