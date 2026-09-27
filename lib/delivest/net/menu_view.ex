defmodule Delivest.Net.MenuView do
  @type product :: %{
          id: binary(),
          name: String.t(),
          old_price: term(),
          price: integer(),
          description: String.t() | nil,
          quantity: integer() | nil,
          weight: integer() | nil,
          is_active: boolean() | nil,
          photo_url: String.t() | nil,
          external_id: String.t() | nil
        }

  @type category :: %{
          id: binary(),
          name: String.t(),
          order: number() | nil,
          is_active: boolean() | nil,
          products: [product()]
        }

  @type t :: [category()]

  def build(categories) when is_list(categories) do
    Enum.map(categories, &build_category/1)
  end

  defp build_category(category) do
    %{
      id: category.id,
      name: category.name,
      order: Map.get(category, :order),
      is_active: Map.get(category, :is_active),
      products: Enum.map(category.products || [], &build_product/1)
    }
  end

  defp build_product(product) do
    %{
      id: product.id,
      name: product.name,
      old_price: Map.get(product, :old_price),
      price: product.price,
      description: Map.get(product, :description),
      quantity: Map.get(product, :quantity),
      weight: Map.get(product, :weight),
      is_active: Map.get(product, :is_active),
      photo_url: Delivest.Media.get_url_from_file(product.media),
      external_id: Map.get(product, :external_id)
    }
  end
end
