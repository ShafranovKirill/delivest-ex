defmodule Delivest.Promo.Redemption do
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "promo_redemptions" do
    field :promotion_id, :binary_id
    field :promo_code_id, :binary_id
    field :order_id, :binary_id
    field :client_id, :binary_id
    field :discount, :integer, default: 0

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
