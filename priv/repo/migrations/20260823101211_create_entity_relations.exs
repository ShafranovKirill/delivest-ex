defmodule Delivest.Repo.Migrations.CreateEntityRelations do
  use Ecto.Migration

  def change do
    create table(:entity_relations, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")

      add :from_entity_type, :string, null: false
      add :from_id, :binary_id, null: false

      add :to_entity_type, :string, null: false
      add :to_id, :binary_id, null: false

      add :payload, :map, default: %{}

      timestamps()
    end

    create index(:entity_relations, [:to_entity_type, :to_id])

    create index(:entity_relations, [:from_entity_type, :from_id])

    create unique_index(
             :entity_relations,
             [
               :from_entity_type,
               :from_id,
               :to_entity_type,
               :to_id
             ],
             name: :entity_relations_unique_index
           )
  end
end
