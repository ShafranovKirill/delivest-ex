defmodule Delivest.Repo.Migrations.MakeOrderNumberNonUnique do
  use Ecto.Migration

  def change do
    drop unique_index(:orders, [:number])
    create index(:orders, [:number])
  end
end
