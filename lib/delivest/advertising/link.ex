defmodule Delivest.Advertising.Link do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "advertising_links" do
    field :branch_id, :binary_id
    field :token, :string
    field :campaign, :string
    field :name, :string
    field :enabled, :boolean, default: true
    field :archived_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(link, attrs) do
    link
    |> cast(attrs, [:campaign, :name])
    |> validate_required([:campaign, :name])
    |> validate_format(:campaign, ~r/^[a-z0-9]+(?:[-_][a-z0-9]+)*$/)
    |> validate_length(:campaign, max: 64)
    |> validate_length(:name, min: 1, max: 120)
  end
end
