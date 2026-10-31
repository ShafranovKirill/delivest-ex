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
    field :title, :string
    field :price, :integer
    field :base_price, :integer
    field :gift, :boolean, default: false
    field :quantity, :integer, default: 1
    field :category_id, :binary_id
    field :category_name, :string
    field :stars_spent, :integer, default: 0

    belongs_to :order, Order

    has_many :modifiers, Delivest.Oms.OrderItemModifier,
      on_delete: :delete_all,
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  def modifier_names(%{modifiers: modifiers}) when is_list(modifiers) do
    Enum.map(modifiers, fn
      %{quantity: quantity, name: name} when quantity > 1 -> "#{name} ×#{quantity}"
      %{name: name} -> name
    end)
  end

  def modifier_names(_item), do: []

  def full_title(item) do
    case modifier_names(item) do
      [] -> item.title
      names -> "#{item.title} (#{Enum.join(names, ", ")})"
    end
  end

  def selection(%__MODULE__{modifiers: modifiers}) when is_list(modifiers) do
    modifiers
    |> Enum.reject(&is_nil(&1.modifier_id))
    |> Enum.map(&%{"id" => &1.modifier_id, "quantity" => &1.quantity})
  end

  def selection(_item), do: []

  def changeset(order_item, attrs) do
    order_item
    |> cast(attrs, [
      :order_id,
      :product_id,
      :title,
      :price,
      :base_price,
      :gift,
      :quantity,
      :category_id,
      :category_name,
      :stars_spent
    ])
    |> cast_assoc(:modifiers)
    |> validate_required([:product_id, :title, :price, :quantity])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:price, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:order_id)
  end
end
