defmodule Delivest.Net.MenuView do
  @type product :: %{
          id: binary(),
          name: String.t(),
          price: integer(),
          photo_url: String.t() | nil
        }

  @type category :: %{
          id: binary(),
          name: String.t(),
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
      products: Enum.map(category.products, &build_product/1)
    }
  end

  defp build_product(product) do
    %{
      id: product.id,
      name: product.name,
      price: product.price,
      photo_url: Delivest.Media.get_url_from_file(product.media)
    }
  end
end
