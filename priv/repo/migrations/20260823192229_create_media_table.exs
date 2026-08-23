defmodule Delivest.Repo.Migrations.CreateMediaTable do
  use Ecto.Migration

  def change do
    create table(:media_files, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :bucket, :string, null: false
      add :key, :string, null: false
      add :original_name, :string, null: false
      add :mime_type, :string, null: false
      add :size, :bigint, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:media_files, [:bucket, :key])
  end
end
