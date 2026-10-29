defmodule Delivest.Oms.Orders.Assembler do
  alias Delivest.Identity.Client
  alias Delivest.Oms.Order
  alias Delivest.Repo
  alias Delivest.Oms.Order.AppliedPromotion

  def changeset(
        %Order{} = order,
        attrs,
        %{cart: cart, lines: lines, client_id: client_id, pricing: pricing} = changes
      ) do
    delivery = Map.get(changes, :delivery, 0)

    params =
      attrs
      |> snapshot(client_id, order)
      |> Map.merge(%{
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

  defp snapshot(attrs, nil, _order), do: attrs
  defp snapshot(attrs, client_id, %Order{client_id: client_id}), do: attrs

  defp snapshot(attrs, client_id, _order) do
    case Repo.get(Client, client_id) do
      %Client{} = client ->
        attrs
        |> put_blank("customer_phone", client.phone)
        |> put_blank("customer_name", client.name)

      nil ->
        attrs
    end
  end

  defp put_blank(attrs, key, value) do
    if attrs[key] in [nil, ""], do: Map.put(attrs, key, value), else: attrs
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
