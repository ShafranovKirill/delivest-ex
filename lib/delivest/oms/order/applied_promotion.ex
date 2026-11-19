defmodule Delivest.Oms.Order.AppliedPromotion do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field :promotion_id, :binary_id
    field :promo_code_id, :binary_id
    field :name, :string
    field :code, :string
    field :gift_product_ids, {:array, :binary_id}, default: []
    field :discount, :integer, default: 0
    field :crm_certificate, :map
    field :certificate_export_mode, :string
  end

  def changeset(applied, attrs) do
    applied
    |> cast(attrs, [
      :promotion_id,
      :promo_code_id,
      :name,
      :code,
      :discount,
      :gift_product_ids,
      :crm_certificate,
      :certificate_export_mode
    ])
    |> validate_required([:promotion_id, :name])
  end
end
