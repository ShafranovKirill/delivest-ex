defmodule Delivest.Promo.Line do
  @type t :: %__MODULE__{
          key: String.t(),
          product_id: binary(),
          name: String.t(),
          image_url: String.t() | nil,
          base_price: non_neg_integer(),
          quantity: pos_integer(),
          total: non_neg_integer(),
          stars: non_neg_integer(),
          gift: boolean(),
          promotion_ids: [binary()],
          modifiers: [map()]
        }

  defstruct [
    :key,
    :product_id,
    :name,
    :image_url,
    base_price: 0,
    quantity: 1,
    total: 0,
    stars: 0,
    stars_reward: 0,
    gift: false,
    promotion_ids: [],
    modifiers: []
  ]

  def paid(item) do
    %__MODULE__{
      key: Map.get(item, :key, item.product_id),
      product_id: item.product_id,
      modifiers: Map.get(item, :modifiers, []),
      name: item.name,
      image_url: item.image_url,
      base_price: item.price,
      quantity: item.quantity,
      total: item.price * item.quantity
    }
  end

  def gift(product, quantity, promotion_id) do
    %__MODULE__{
      key: "gift:#{promotion_id}:#{product.id}",
      product_id: product.id,
      name: product.name,
      image_url: Delivest.Media.thumb_url_from_file(product.media),
      base_price: product.price,
      quantity: quantity,
      total: 0,
      gift: true,
      promotion_ids: [promotion_id]
    }
  end

  def extra(%__MODULE__{modifiers: modifiers}) when is_list(modifiers),
    do: modifiers |> Enum.map(&(price(&1) * quantity(&1))) |> Enum.sum()

  def extra(_line), do: 0

  defp price(%{price: price}) when is_integer(price), do: price
  defp price(%{"price" => price}) when is_integer(price), do: price
  defp price(_modifier), do: 0

  defp quantity(%{quantity: quantity}) when is_integer(quantity), do: quantity
  defp quantity(%{"quantity" => quantity}) when is_integer(quantity), do: quantity
  defp quantity(_modifier), do: 1

  def base_total(%__MODULE__{base_price: price, quantity: quantity}), do: price * quantity

  def discount(%__MODULE__{} = line), do: base_total(line) - line.total

  def reduce(%__MODULE__{} = line, amount, promotion_id) do
    %{
      line
      | total: line.total - amount,
        promotion_ids: Enum.uniq([promotion_id | line.promotion_ids])
    }
  end
end
