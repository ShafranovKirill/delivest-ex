defmodule DelivestWeb.Client.Order.OrderJSON do
  alias Delivest.Couriers
  alias Delivest.Media
  alias Delivest.Net
  alias Delivest.Oms.Order

  def create(%{order: order, confirmation_url: url}) do
    %{data: order |> order_data() |> Map.put(:payment, payment_data(order, url))}
  end

  def create(%{order: order}) do
    %{data: order_data(order)}
  end

  def active(%{orders: orders}) do
    %{data: active_orders_data(orders)}
  end

  def index(%{orders: orders}) do
    %{data: active_orders_data(orders)}
  end

  defp active_orders_data(orders) do
    settings = Delivest.Oms.Orders.client_cancellation_settings(orders)
    Enum.map(orders, &active_order_data(&1, Map.get(settings, &1.branch_id, true)))
  end

  def active_order_data(order),
    do: active_order_data(order, Delivest.Oms.Orders.client_cancellable?(order))

  defp active_order_data(order, enabled?) do
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
      can_cancel: Delivest.Oms.Orders.client_cancellable?(order, enabled?),
      items: Enum.map(order.items, &item_data/1)
    }
  end

  defp payment_data(%{awaiting_payment: true}, url) when is_binary(url),
    do: %{confirmation_url: url}

  defp payment_data(_order, _url), do: nil

  defp order_data(order) do
    items = order.items || []
    product_ids = items |> Enum.map(& &1.product_id) |> Enum.uniq()

    products =
      Net.Products.list_branch_cart_products_by_ids(order.branch_id, product_ids,
        preload: [:media]
      )

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
      inserted_at: order.inserted_at,
      client_id: order.client_id,
      cook_by: order.cook_by,
      comment: order.comment,
      customer_phone: order.customer_phone,
      customer_phone_ext: order.customer_phone_ext,
      customer_name: order.customer_name,
      persons: order.persons,
      address: serialize_address(order.address),
      items: Enum.map(items, &item_data(&1, products))
    }
  end

  defp item_data(item, products \\ %{}) do
    image_url =
      case Map.get(products, item.product_id) do
        nil -> nil
        product -> Media.thumb_url_from_file(product.media)
      end

    %{
      product_id: item.product_id,
      image_url: image_url,
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
