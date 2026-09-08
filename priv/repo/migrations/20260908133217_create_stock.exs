defmodule Delivest.Repo.Migrations.CreateStock do
  use Ecto.Migration

  def change do
    create table(:stocks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :media_id, :string, null: false
      add :text, :string
      add :is_active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end
  end
end
