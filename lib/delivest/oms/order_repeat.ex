defmodule Delivest.Oms.OrderRepeat do
  alias Delivest.Oms.{Carts, Order, OrderItem, Orders}

  def run(cart_id, client_id, order_id) do
    case Orders.get_client_order(client_id, order_id) do
      %Order{} = order -> Carts.add_items(cart_id, lines(order))
      nil -> {:error, :order_not_found}
    end
  end

  defp lines(%Order{items: items}) do
    items
    |> Enum.reject(&(&1.gift or is_nil(&1.product_id)))
    |> Enum.group_by(&{&1.product_id, OrderItem.selection(&1)}, & &1.quantity)
    |> Enum.map(fn {{product_id, selection}, quantities} ->
      {product_id, Enum.sum(quantities), selection}
    end)
  end
end
