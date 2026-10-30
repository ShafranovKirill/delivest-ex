defmodule Delivest.Promo.Result do
  alias Delivest.Promo.{Basket, Compiled, Line, PromoCode}

  @type applied :: %{
          promotion_id: binary(),
          promo_code_id: binary() | nil,
          code: String.t() | nil,
          name: String.t(),
          description: String.t() | nil,
          discount: non_neg_integer(),
          gifts: [%{product_id: binary(), name: String.t(), quantity: pos_integer()}]
        }

  @type hint :: %{
          promotion_id: binary(),
          name: String.t(),
          description: String.t() | nil,
          reasons: [map()]
        }

  @type code_state :: %{
          code: String.t(),
          status: :applied | :pending | :rejected,
          reason: atom() | nil,
          reasons: [map()],
          name: String.t() | nil
        }

  @type t :: %__MODULE__{
          lines: [Line.t()],
          subtotal: non_neg_integer(),
          discount: non_neg_integer(),
          total: non_neg_integer(),
          points: non_neg_integer(),
          applied: [applied()],
          hints: [hint()],
          code: code_state() | nil
        }

  defstruct lines: [],
            subtotal: 0,
            discount: 0,
            total: 0,
            points: 0,
            applied: [],
            hints: [],
            code: nil

  def build(%Basket{} = basket, selected, code, hints, code_state) do
    subtotal = Basket.subtotal(basket)
    total = Basket.total(basket)

    %__MODULE__{
      lines: basket.lines,
      subtotal: subtotal,
      total: total,
      discount: subtotal - total,
      applied: selected |> Enum.map(&applied(&1, basket, code)) |> Enum.filter(&effective?/1),
      hints: hints,
      code: code_state
    }
  end

  def hint(%Compiled{promotion: promotion}, reasons) do
    %{
      promotion_id: promotion.id,
      name: promotion.name,
      description: promotion.description,
      reasons: reasons
    }
  end

  def code_state(code, status, opts \\ []) do
    %{
      code: code,
      status: status,
      reason: opts[:reason],
      reasons: Keyword.get(opts, :reasons, []),
      name: opts[:name]
    }
  end

  def promo_code(%__MODULE__{applied: applied}) do
    Enum.find_value(applied, fn
      %{promo_code_id: id, code: code} when not is_nil(id) -> {id, code}
      _applied -> nil
    end)
  end

  defp applied(%Compiled{promotion: promotion}, basket, code) do
    {code_id, code_text} = code_of(promotion.id, code)

    %{
      promotion_id: promotion.id,
      promo_code_id: code_id,
      code: code_text,
      name: promotion.name,
      description: promotion.description,
      discount: Basket.discount_for(basket, promotion.id),
      gifts: gifts(basket, promotion.id)
    }
  end

  defp effective?(%{code: code}) when is_binary(code), do: true
  defp effective?(%{discount: discount, gifts: gifts}), do: discount > 0 or gifts != []

  defp code_of(promotion_id, %PromoCode{promotion_id: promotion_id} = code),
    do: {code.id, code.code}

  defp code_of(_promotion_id, _code), do: {nil, nil}

  defp gifts(basket, promotion_id) do
    for line <- Basket.gifts(basket), promotion_id in line.promotion_ids do
      %{product_id: line.product_id, name: line.name, quantity: line.quantity}
    end
  end
end
