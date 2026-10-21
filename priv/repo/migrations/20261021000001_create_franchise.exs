defmodule Delivest.Repo.Migrations.CreateFranchise do
  use Ecto.Migration

  def change do
    create table(:franchise_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :primary_color, :string, null: false
      add :legal_form, :string
      add :legal_name, :string
      add :inn, :string
      add :ogrn, :string
      add :legal_address, :text
      add :email, :string
      add :phone, :string

      timestamps(type: :utc_datetime)
    end

    create table(:legal_documents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :kind, :string, null: false
      add :body, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:legal_documents, [:kind])
  end
end
