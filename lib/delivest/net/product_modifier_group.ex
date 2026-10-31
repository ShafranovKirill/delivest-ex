defmodule Delivest.Net.ProductModifierGroup do
  use Ecto.Schema

  @primary_key false
  @foreign_key_type :binary_id

  schema "product_modifier_groups" do
    belongs_to :product, Delivest.Net.Product, primary_key: true
    belongs_to :group, Delivest.Net.ModifierGroup, primary_key: true
    field :position, :integer, default: 0
  end
end
