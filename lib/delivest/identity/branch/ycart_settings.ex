defmodule Delivest.Identity.Branch.YcartSettings do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  @derive {Jason.Encoder, only: [:enabled, :yandex_org_id]}

  embedded_schema do
    field :enabled, :boolean, default: false
    field :yandex_org_id, :string
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:enabled, :yandex_org_id])
  end
end
