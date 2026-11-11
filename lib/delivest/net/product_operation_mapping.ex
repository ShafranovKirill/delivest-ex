defmodule Delivest.Net.ProductOperationMapping do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "product_operation_mappings" do
    field :source_key, :string
    field :entity_type, :string
    field :target_entity_id, :binary_id
    belongs_to :target_branch, Delivest.Identity.Branch, type: :binary_id
    timestamps(type: :utc_datetime)
  end

  def changeset(mapping, attrs) do
    mapping
    |> cast(attrs, [:source_key, :entity_type, :target_entity_id, :target_branch_id])
    |> validate_required([:source_key, :entity_type, :target_entity_id, :target_branch_id])
    |> validate_length(:source_key, max: 128)
    |> unique_constraint([:source_key, :target_branch_id, :entity_type],
      name: :product_operation_mapping_source_index
    )
    |> unique_constraint([:target_branch_id, :entity_type, :target_entity_id],
      name: :product_operation_mapping_target_index
    )
  end
end
