defmodule DelivestWeb.Client.Order.OrderJSON do
  alias Delivest.Couriers
  alias Delivest.Oms.Order

  def create(%{order: order, confirmation_url: url}) do
    %{data: order |> order_data() |> Map.put(:payment, payment_data(order, url))}
  end

  def create(%{order: order}) do
    %{data: order_data(order)}
  end

  def active(%{orders: orders}) do
    %{data: Enum.map(orders, &active_order_data/1)}
  end

  def index(%{orders: orders}) do
    %{data: Enum.map(orders, &active_order_data/1)}
  end

  def active_order_data(order) do
    %{
      id: order.id,
      number: order.number,
      short_number: Order.short_number(order),
      status: order.status,
      fulfillment_type: order.fulfillment_type,
      payment_method: order.payment_method,
      awaiting_payment: order.awaiting_payment,
      total_amount: order.total_amount,
      points_earned: order.points_earned || 0,
      subtotal_amount: order.subtotal_amount || order.total_amount,
      discount_amount: order.discount_amount || 0,
      delivery_amount: order.delivery_amount || 0,
      promotions: Enum.map(order.promotions || [], &promotion_data/1),
      branch_id: order.branch_id,
      cook_by: order.cook_by,
      comment: order.comment,
      address: serialize_address(order.address),
      inserted_at: order.inserted_at,
      courier: Couriers.contact(order),
      can_cancel: Delivest.Oms.Orders.client_cancellable?(order),
      items: Enum.map(order.items, &item_data/1)
    }
  end

  defp payment_data(%{awaiting_payment: true}, url) when is_binary(url),
    do: %{confirmation_url: url}

  defp payment_data(_order, _url), do: nil

  defp order_data(order) do
    %{
      id: order.id,
      number: order.number,
      short_number: Order.short_number(order),
      status: order.status,
      fulfillment_type: order.fulfillment_type,
      payment_method: order.payment_method,
      awaiting_payment: order.awaiting_payment,
      total_amount: order.total_amount,
      points_earned: order.points_earned || 0,
      subtotal_amount: order.subtotal_amount || order.total_amount,
      discount_amount: order.discount_amount || 0,
      delivery_amount: order.delivery_amount || 0,
      promotions: Enum.map(order.promotions || [], &promotion_data/1),
      branch_id: order.branch_id,
      cart_id: order.cart_id,
      client_id: order.client_id,
      cook_by: order.cook_by,
      comment: order.comment,
      customer_phone: order.customer_phone,
      customer_phone_ext: order.customer_phone_ext,
      customer_name: order.customer_name,
      persons: order.persons,
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
      stars_reward: item.stars_reward,
      quantity: item.quantity,
      modifiers: modifiers(item)
    }
  end

  defp modifiers(%{modifiers: modifiers}) when is_list(modifiers),
    do: Enum.map(modifiers, &DelivestWeb.Client.Cart.CartJSON.modifier/1)

  defp modifiers(_item), do: []

  defp promotion_data(promotion) do
    %{name: promotion.name, code: promotion.code, discount: promotion.discount}
  end

  defp serialize_address(%Ecto.Changeset{} = _address), do: nil
  defp serialize_address(%{} = address), do: Map.from_struct(address)
  defp serialize_address(_), do: nil
end
