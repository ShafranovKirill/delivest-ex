defmodule Delivest.Repo.Migrations.AddNutrientsAndExciseToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :calories, :float
      add :proteins, :float
      add :fats, :float
      add :carbohydrates, :float
      add :excise, :string
    end
  end
end
