defmodule Delivest.Oms.Orders.Assembler do
  alias Delivest.Oms.Order
  alias Delivest.Oms.Order.AppliedPromotion

  def changeset(
        %Order{} = order,
        attrs,
        %{cart: cart, lines: lines, client_id: client_id, pricing: pricing} = changes
      ) do
    delivery = Map.get(changes, :delivery, 0)

    params =
      Map.merge(attrs, %{
        "cart_id" => cart.id,
        "branch_id" => cart.branch_id,
        "client_id" => client_id,
        "total_amount" => lines.total_amount + delivery,
        "subtotal_amount" => pricing.subtotal,
        "discount_amount" => pricing.discount,
        "delivery_amount" => delivery
      })

    order
    |> Order.changeset(params)
    |> Ecto.Changeset.put_assoc(:items, lines.items)
    |> Ecto.Changeset.put_embed(:promotions, Enum.map(pricing.applied, &applied/1))
  end

  defp applied(applied) do
    %AppliedPromotion{
      promotion_id: applied.promotion_id,
      promo_code_id: applied.promo_code_id,
      name: applied.name,
      code: applied.code,
      discount: applied.discount
    }
  end
end
