defmodule Delivest.Oms.Orders.DraftCart do
  alias Delivest.Oms.{Carts, Order}

  def create(%Order{} = order) do
    with {:ok, cart} <- Carts.create_cart(%{branch_id: order.branch_id}) do
      {:ok, populate(order, cart.id)}
    end
  end

  def populate(%Order{} = order, cart_id) do
    Carts.clear_cart(cart_id)
    Enum.each(order.items, &Carts.add_item(cart_id, &1.product_id, &1.quantity))
    Carts.get_cart_by_id(cart_id)
  end
end
