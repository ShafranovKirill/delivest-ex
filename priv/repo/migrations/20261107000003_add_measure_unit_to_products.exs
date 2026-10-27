defmodule Delivest.Repo.Migrations.AddMeasureUnitToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :measure_unit, :string, null: false, default: "g"
    end
  end
end
