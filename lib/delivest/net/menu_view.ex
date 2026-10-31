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
          measure_unit: String.t(),
          nutrition: map() | nil,
          is_active: boolean() | nil,
          tags: [%{id: binary(), name: String.t(), icon_url: String.t() | nil}],
          suggested: boolean(),
          photo_url: String.t() | nil
        }

  @type category :: %{
          id: binary(),
          name: String.t(),
          order: number() | nil,
          is_active: boolean() | nil,
          products: [product()]
        }

  @type t :: [category()]

  def build(categories, tags \\ %{}) when is_list(categories) do
    Enum.map(categories, &build_category(&1, tags))
  end

  defp build_category(category, tags) do
    %{
      id: category.id,
      name: category.name,
      order: Map.get(category, :order),
      is_active: Map.get(category, :is_active),
      products: Enum.map(category.products || [], &build_product(&1, tags))
    }
  end

  @nutrients [:calories, :proteins, :fats, :carbohydrates]

  defp nutrition(product) do
    values = Map.new(@nutrients, &{&1, Map.get(product, &1)})
    if Enum.all?(values, fn {_key, value} -> is_nil(value) end), do: nil, else: values
  end

  defp build_product(product, tags) do
    %{
      id: product.id,
      name: product.name,
      slug: Map.get(product, :slug),
      old_price: Map.get(product, :old_price),
      price: product.price,
      stars_reward: Map.get(product, :stars_reward),
      description: Map.get(product, :description),
      quantity: Map.get(product, :quantity),
      weight: Map.get(product, :weight),
      measure_unit: to_string(Map.get(product, :measure_unit) || :g),
      nutrition: nutrition(product),
      is_active: Map.get(product, :is_active),
      tags: product |> Map.get(:tags, []) |> Enum.flat_map(&List.wrap(tags[&1])),
      suggested: Map.get(product, :suggested, false),
      photo_url: Delivest.Media.thumb_url_from_file(product.media)
    }
  end
end
