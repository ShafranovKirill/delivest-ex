defmodule Delivest.Net.ProductTag do
  use Ecto.Schema
  import Ecto.Changeset

  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.Net.TagIcons

  @type t :: %__MODULE__{}
  @primary_key {:id, :binary_id, autogenerate: true}

  schema "product_tags" do
    field :name, :string
    field :icon, :string
    field :icon_key, :string
    field :order, :float, default: 0.0

    timestamps(type: :utc_datetime)
  end

  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:name, :icon], empty_values: [nil, ""])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 24)
    |> validate_inclusion(:icon, TagIcons.names())
  end

  def require_icon(changeset) do
    if get_field(changeset, :icon) || get_field(changeset, :icon_key),
      do: changeset,
      else: add_error(changeset, :icon, gettext("Pick an icon or upload your own"))
  end
end
