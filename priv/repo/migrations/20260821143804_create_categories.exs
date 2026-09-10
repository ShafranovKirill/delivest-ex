defmodule Delivest.Repo.Migrations.CreateCategories do
  use Ecto.Migration

  def change do
    create table(:categories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :order, :float, null: false
      add :is_active, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end
  end
end
