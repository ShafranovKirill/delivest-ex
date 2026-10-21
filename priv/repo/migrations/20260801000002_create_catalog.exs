defmodule Delivest.Repo.Migrations.CreateCatalog do
  use Ecto.Migration

  def change do
    create table(:media_files, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :bucket, :string, null: false
      add :key, :string, null: false
      add :original_name, :string, null: false
      add :mime_type, :string, null: false
      add :size, :bigint, null: false
      add :context, :string, null: false
      add :owner_id, :binary_id, null: false
      add :is_private, :boolean, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:media_files, [:bucket, :key])

    create table(:categories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :order, :float, null: false
      add :is_active, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create table(:products, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string
      add :price, :integer, null: false
      add :old_price, :string
      add :description, :text
      add :quantity, :integer
      add :weight, :integer
      add :is_active, :boolean, null: false, default: true
      add :external_id, :string
      add :category_id, references(:categories, type: :binary_id, on_delete: :nilify_all)
      add :media_id, :binary_id
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:products, [:slug])

    create table(:entity_relations, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :from_entity_type, :string, null: false
      add :from_id, :binary_id, null: false
      add :to_entity_type, :string, null: false
      add :to_id, :binary_id, null: false
      add :payload, :map, default: %{}

      timestamps()
    end

    create index(:entity_relations, [:from_entity_type, :from_id])
    create index(:entity_relations, [:to_entity_type, :to_id])

    create unique_index(:entity_relations, [:from_entity_type, :from_id, :to_entity_type, :to_id],
             name: :entity_relations_unique_index
           )

    create table(:stocks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :media_id, :binary_id, null: false
      add :product_id, references(:products, type: :binary_id, on_delete: :nilify_all)
      add :text, :string
      add :order, :float, null: false
      add :is_active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:stocks, [:product_id])
  end
end
