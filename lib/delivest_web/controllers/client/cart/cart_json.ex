defmodule DelivestWeb.Client.Cart.CartJSON do
  alias Delivest.Oms.CartView
  alias DelivestWeb.Client.Cart.PromoJSON

  def show(%{cart: %CartView{} = cart}) do
    %{data: cart_data(cart)}
  end

  def show(%{cart: nil}) do
    %{data: nil}
  end

  defp cart_data(%CartView{} = cart) do
    %{
      id: cart.id,
      session_id: cart.session_id,
      branch_id: cart.branch_id,
      fulfillment_type: cart.fulfillment_type,
      items: Enum.map(cart.items, &item_data/1),
      total_quantity: cart.total_quantity,
      subtotal_amount: cart.subtotal_amount,
      discount_amount: cart.discount_amount,
      total_amount: cart.total_amount,
      promo_code: PromoJSON.code(cart.code),
      promotions: Enum.map(cart.promotions, &PromoJSON.applied/1),
      hints: Enum.map(cart.hints, &PromoJSON.hint/1)
    }
  end

  defp item_data(item) do
    %{
      key: Map.get(item, :key, item.product_id),
      product_id: item.product_id,
      name: item.name,
      image_url: item.image_url,
      price: item.price,
      quantity: item.quantity,
      total_price: item.total_price,
      base_total: Map.get(item, :base_total, item.total_price),
      gift: Map.get(item, :gift, false),
      promotion_ids: Map.get(item, :promotion_ids, [])
    }
  end
end
