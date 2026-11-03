defmodule Delivest.SiteSnapshot.Installation do
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "site_snapshot_installation" do
    field :installation_id, Ecto.UUID
  end
end
