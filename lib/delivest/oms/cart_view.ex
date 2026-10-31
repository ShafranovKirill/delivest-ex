defmodule Delivest.Oms.CartView do
  alias Delivest.Promo.{Line, Result}

  @type item :: %{
          required(:product_id) => binary(),
          required(:name) => String.t(),
          required(:image_url) => String.t() | nil,
          required(:price) => integer(),
          required(:quantity) => integer(),
          required(:total_price) => integer(),
          optional(:key) => String.t(),
          optional(:base_total) => integer(),
          optional(:gift) => boolean(),
          optional(:stars) => boolean(),
          optional(:promotion_ids) => [binary()]
        }

  @type t :: %__MODULE__{
          id: binary(),
          session_id: String.t() | nil,
          staff_id: binary() | nil,
          branch_id: binary() | nil,
          client_id: binary() | nil,
          fulfillment_type: String.t() | nil,
          promo_code: String.t() | nil,
          items: [item()],
          total_quantity: non_neg_integer(),
          subtotal_amount: non_neg_integer(),
          discount_amount: non_neg_integer(),
          total_amount: non_neg_integer(),
          promotions: [Result.applied()],
          hints: [Result.hint()],
          code: Result.code_state() | nil
        }

  defstruct [
    :id,
    :session_id,
    :staff_id,
    :branch_id,
    :client_id,
    :fulfillment_type,
    :promo_code,
    :code,
    items: [],
    total_quantity: 0,
    subtotal_amount: 0,
    discount_amount: 0,
    total_amount: 0,
    promotions: [],
    hints: []
  ]

  def base_items(%__MODULE__{items: items}),
    do: Enum.reject(items, &(Map.get(&1, :gift, false) or Map.get(&1, :stars, false)))

  def star_items(%__MODULE__{items: items}), do: Enum.filter(items, &Map.get(&1, :stars, false))

  def with_pricing(%__MODULE__{} = view, %Result{} = result) do
    %{
      view
      | items: Enum.map(result.lines, &item/1) ++ star_items(view),
        subtotal_amount: result.subtotal,
        discount_amount: result.discount,
        total_amount: result.total,
        promotions: result.applied,
        hints: result.hints,
        code: result.code
    }
  end

  defp item(%Line{} = line) do
    %{
      key: line.key,
      product_id: line.product_id,
      name: line.name,
      image_url: line.image_url,
      price: line.base_price,
      quantity: line.quantity,
      total_price: line.total,
      base_total: Line.base_total(line),
      gift: line.gift,
      promotion_ids: line.promotion_ids,
      modifiers: line.modifiers
    }
  end
end
