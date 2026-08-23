defmodule Delivest.Relations.EntityRelation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "entity_relations" do
    field :from_entity_type, :string
    field :from_id, Ecto.UUID
    field :to_entity_type, :string
    field :to_id, Ecto.UUID
    field :payload, :map, default: %{}

    timestamps()
  end

  @doc false
  def changeset(entity_relation, attrs) do
    entity_relation
    |> cast(attrs, [:from_entity_type, :from_id, :to_entity_type, :to_id, :payload])
    |> validate_required([:from_entity_type, :from_id, :to_entity_type, :to_id])
    |> unique_constraint([:from_entity_type, :from_id, :to_entity_type, :to_id],
      name: :entity_relations_unique_index
    )
  end
end
