defmodule Delivest.Repo.Migrations.AddCookByToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :cook_by, :naive_datetime
    end
  end
end
