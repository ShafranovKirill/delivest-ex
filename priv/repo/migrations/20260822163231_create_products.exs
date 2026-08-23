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

      add :category_id, references(:categories, type: :binary_id, on_delete: :nilify_all),
        null: false

      add :media_id, :binary_id

      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end
  end
end
