defmodule Delivest.SiteSnapshot.Mapping do
  use Ecto.Schema

  @primary_key false
  schema "site_snapshot_mappings" do
    field :source_installation_id, Ecto.UUID
    field :target_branch_id, Ecto.UUID
    field :entity_type, :string
    field :source_id, Ecto.UUID
    field :target_id, Ecto.UUID
  end
end
