defmodule Delivest.Oms.OrderItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Oms.Order

  use Gettext, backend: DelivestWeb.Gettext

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "order_items" do
    field :product_id, :binary_id
    field :price, :decimal
    field :quantity, :integer, default: 1

    belongs_to :order, Order

    timestamps(type: :utc_datetime)
  end

  def changeset(order_item, attrs) do
    order_item
    |> cast(attrs, [:order_id, :product_id, :price, :quantity])
    |> validate_required([:order_id, :product_id, :price, :quantity])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:price, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:order_id)
  end
end
