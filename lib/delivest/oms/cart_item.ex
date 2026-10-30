defmodule Delivest.Oms.CartItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Oms.Cart

  @type t :: %__MODULE__{}

  @max_quantity 99

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "cart_items" do
    field :product_id, :binary_id
    field :quantity, :integer, default: 1
    field :modifiers, {:array, :map}, default: []
    field :modifier_key, :string, default: ""

    belongs_to :cart, Cart

    timestamps(type: :utc_datetime_usec)
  end

  def max_quantity, do: @max_quantity

  def changeset(cart_item, attrs) do
    cart_item
    |> cast(attrs, [:cart_id, :product_id, :quantity, :modifiers, :modifier_key],
      empty_values: []
    )
    |> validate_required([:cart_id, :product_id, :quantity])
    |> validate_number(:quantity, greater_than: 0, less_than_or_equal_to: @max_quantity)
    |> foreign_key_constraint(:cart_id)
    |> unique_constraint([:cart_id, :product_id, :modifier_key],
      name: :cart_items_cart_id_product_id_modifier_key_index
    )
  end
end
