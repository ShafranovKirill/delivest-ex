defmodule Delivest.Repo.Migrations.CreateProducts do
  use Ecto.Migration

  def change do
    create table(:products, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :price, :integer, null: false
      add :description, :text
      add :is_active, :boolean, null: false, default: true
      add :external_id, :string

      timestamps(type: :utc_datetime)
    end
  end
end
