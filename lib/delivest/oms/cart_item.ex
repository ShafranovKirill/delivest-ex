defmodule Delivest.Oms.CartItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Oms.Cart

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "cart_items" do
    field :product_id, :binary_id
    field :quantity, :integer, default: 1

    belongs_to :cart, Cart

    timestamps(type: :utc_datetime)
  end

  def changeset(cart_item, attrs) do
    cart_item
    |> cast(attrs, [:cart_id, :product_id, :quantity])
    |> validate_required([:cart_id, :product_id, :quantity])
    |> validate_number(:quantity, greater_than: 0)
    |> foreign_key_constraint(:cart_id)
    |> unique_constraint([:cart_id, :product_id], name: :cart_items_cart_id_product_id_index)
  end
end
