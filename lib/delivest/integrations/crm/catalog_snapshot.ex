defmodule Delivest.Integrations.Crm.CatalogSnapshot do
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "crm_catalog_snapshots" do
    field :branch_id, :binary_id
    field :provider, :string
    field :products, {:array, :map}, default: []
    field :checked_at, :utc_datetime
  end
end
