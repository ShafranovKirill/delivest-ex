defmodule Delivest.Oms.Orders.DraftCart do
  alias Delivest.Oms.{Carts, Order}

  def create(%Order{} = order) do
    with {:ok, cart} <- Carts.create_cart(%{branch_id: order.branch_id}) do
      {:ok, populate(order, cart.id)}
    end
  end

  def populate(%Order{} = order, cart_id) do
    Carts.clear_cart(cart_id)

    order.items
    |> Enum.reject(& &1.gift)
    |> Enum.each(&Carts.add_item(cart_id, &1.product_id, &1.quantity))

    {:ok, cart} = Carts.update_context(cart_id, context(order))
    cart
  end

  defp context(%Order{} = order) do
    %{
      promo_code: Enum.find_value(order.promotions || [], & &1.code),
      fulfillment_type: order.fulfillment_type && to_string(order.fulfillment_type),
      client_id: order.client_id
    }
  end
end
