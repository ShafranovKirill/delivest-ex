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
    field :discount, :integer, default: 0
  end

  def changeset(applied, attrs) do
    applied
    |> cast(attrs, [:promotion_id, :promo_code_id, :name, :code, :discount])
    |> validate_required([:promotion_id, :name])
  end
end
