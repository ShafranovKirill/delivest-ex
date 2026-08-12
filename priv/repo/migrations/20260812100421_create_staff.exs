defmodule Delivest.Repo.Migrations.CreateStaff do
  use Ecto.Migration

  def change do
    create table(:staff, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :login, :string, null: false
      add :password_hash, :string, null: false
      add :name, :string

      add :status, :string, default: "active", null: false

      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:staff, [:login], name: :staff__login__uk)
  end
end
