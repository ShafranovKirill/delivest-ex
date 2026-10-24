defmodule Delivest.Net.MenuView do
  @type product :: %{
          id: binary(),
          name: String.t(),
          slug: String.t() | nil,
          old_price: term(),
          price: integer(),
          description: String.t() | nil,
          quantity: integer() | nil,
          weight: integer() | nil,
          is_active: boolean() | nil,
          tags: [atom()],
          suggested: boolean(),
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
      slug: Map.get(product, :slug),
      old_price: Map.get(product, :old_price),
      price: product.price,
      description: Map.get(product, :description),
      quantity: Map.get(product, :quantity),
      weight: Map.get(product, :weight),
      is_active: Map.get(product, :is_active),
      tags: Map.get(product, :tags, []),
      suggested: Map.get(product, :suggested, false),
      photo_url: Delivest.Media.thumb_url_from_file(product.media),
      external_id: Map.get(product, :external_id)
    }
  end
end
