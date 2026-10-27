defmodule Delivest.Net.ProductExternalId do
  use Ecto.Schema
  import Ecto.Changeset

  use Gettext, backend: DelivestWeb.Gettext

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "product_external_ids" do
    belongs_to :product, Delivest.Net.Product
    field :branch_id, :binary_id
    field :provider, :string
    field :external_id, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(external_id, attrs) do
    external_id
    |> cast(attrs, [:branch_id, :provider, :external_id])
    |> update_change(:external_id, &String.trim/1)
    |> validate_required([:branch_id, :provider, :external_id])
    |> validate_length(:external_id, max: 64)
    |> unique_constraint([:branch_id, :provider, :external_id],
      message: gettext("is already used by another product")
    )
  end
end
