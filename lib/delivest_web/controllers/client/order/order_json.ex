defmodule DelivestWeb.Client.Order.OrderJSON do
  alias Delivest.Oms.OrderStatus

  def create(%{order: order}) do
    %{data: order_data(order)}
  end

  def active(%{orders: orders}) do
    %{data: Enum.map(orders, &active_order_data/1)}
  end

  def index(%{orders: orders}) do
    %{data: Enum.map(orders, &active_order_data/1)}
  end

  defp active_order_data(order) do
    %{
      id: order.id,
      number: order.number,
      status: OrderStatus.current(order),
      fulfillment_type: order.fulfillment_type,
      payment_method: order.payment_method,
      total_amount: order.total_amount,
      subtotal_amount: order.subtotal_amount || order.total_amount,
      discount_amount: order.discount_amount || 0,
      promotions: Enum.map(order.promotions || [], &promotion_data/1),
      branch_id: order.branch_id,
      cook_by: order.cook_by,
      comment: order.comment,
      address: serialize_address(order.address),
      inserted_at: order.inserted_at,
      items: Enum.map(order.items, &item_data/1)
    }
  end

  defp order_data(order) do
    %{
      id: order.id,
      number: order.number,
      status: OrderStatus.current(order),
      fulfillment_type: order.fulfillment_type,
      payment_method: order.payment_method,
      total_amount: order.total_amount,
      subtotal_amount: order.subtotal_amount || order.total_amount,
      discount_amount: order.discount_amount || 0,
      promotions: Enum.map(order.promotions || [], &promotion_data/1),
      branch_id: order.branch_id,
      cart_id: order.cart_id,
      client_id: order.client_id,
      cook_by: order.cook_by,
      comment: order.comment,
      customer_phone: order.customer_phone || customer_phone(order),
      customer_name: order.customer_name || customer_name(order),
      address: serialize_address(order.address),
      items: Enum.map(order.items || [], &item_data/1)
    }
  end

  defp item_data(item) do
    %{
      product_id: item.product_id,
      title: item.title,
      price: item.price,
      base_price: item.base_price || item.price,
      gift: item.gift || false,
      quantity: item.quantity
    }
  end

  defp promotion_data(promotion) do
    %{name: promotion.name, code: promotion.code, discount: promotion.discount}
  end

  defp customer_phone(%{client: %_{phone: phone}}), do: phone
  defp customer_phone(_), do: nil

  defp customer_name(%{client: %_{name: name}}), do: name
  defp customer_name(_), do: nil

  defp serialize_address(%Ecto.Changeset{} = _address), do: nil
  defp serialize_address(%{} = address), do: Map.from_struct(address)
  defp serialize_address(_), do: nil
end
