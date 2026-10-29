defmodule Delivest.Oms.OrderItemModifier do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "order_item_modifiers" do
    belongs_to :order_item, Delivest.Oms.OrderItem
    field :modifier_id, :binary_id
    field :group_name, :string
    field :name, :string
    field :price, :integer, default: 0
    field :quantity, :integer, default: 1
  end

  def changeset(modifier, attrs) do
    modifier
    |> cast(attrs, [:modifier_id, :group_name, :name, :price, :quantity])
    |> validate_required([:name, :price, :quantity])
    |> validate_number(:price, greater_than_or_equal_to: 0)
    |> validate_number(:quantity, greater_than: 0)
  end
end
