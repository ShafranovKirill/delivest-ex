defmodule Delivest.Promo.Line do
  @type t :: %__MODULE__{
          key: String.t(),
          product_id: binary(),
          name: String.t(),
          image_url: String.t() | nil,
          base_price: non_neg_integer(),
          quantity: pos_integer(),
          total: non_neg_integer(),
          gift: boolean(),
          promotion_ids: [binary()]
        }

  defstruct [
    :key,
    :product_id,
    :name,
    :image_url,
    base_price: 0,
    quantity: 1,
    total: 0,
    gift: false,
    promotion_ids: []
  ]

  def paid(item) do
    %__MODULE__{
      key: item.product_id,
      product_id: item.product_id,
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
      image_url: Delivest.Media.get_url_from_file(product.media),
      base_price: product.price,
      quantity: quantity,
      total: 0,
      gift: true,
      promotion_ids: [promotion_id]
    }
  end

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
