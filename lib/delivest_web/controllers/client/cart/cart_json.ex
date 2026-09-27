defmodule DelivestWeb.Client.Cart.CartJSON do
  alias Delivest.Oms.CartView

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
      items: Enum.map(cart.items, &item_data/1),
      total_quantity: cart.total_quantity,
      total_amount: cart.total_amount
    }
  end

  defp item_data(item) do
    %{
      product_id: item.product_id,
      name: item.name,
      image_url: item.image_url,
      price: item.price,
      quantity: item.quantity,
      total_price: item.total_price
    }
  end
end
