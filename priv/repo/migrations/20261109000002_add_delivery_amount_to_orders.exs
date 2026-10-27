defmodule Delivest.Repo.Migrations.AddDeliveryAmountToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :delivery_amount, :integer, null: false, default: 0
    end
  end
end
