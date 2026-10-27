defmodule Delivest.Repo.Migrations.CreateProductStops do
  use Ecto.Migration

  def change do
    create table(:product_stops, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :product_id, references(:products, type: :binary_id, on_delete: :delete_all),
        null: false

      add :branch_id, :binary_id, null: false
      add :source, :string, null: false
      add :until, :utc_datetime
      add :staff_id, :binary_id

      timestamps(type: :utc_datetime)
    end

    create unique_index(:product_stops, [:product_id, :source])
    create index(:product_stops, [:branch_id])
  end
end
