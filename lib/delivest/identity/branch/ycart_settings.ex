defmodule Delivest.Identity.Branch.YcartSettings do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  @derive {Jason.Encoder, only: [:yandex_org_id, :latitude, :longitude, :address]}

  embedded_schema do
    field :yandex_org_id, :string
    field :latitude, :float
    field :longitude, :float
    field :address, :string
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:yandex_org_id, :latitude, :longitude, :address])
  end
end
