defmodule Delivest.Oms.Orders.LinesTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Oms.CartView
  alias Delivest.Oms.Orders.Lines

  test "builds order lines and total from the cart" do
    product = insert(:product, price: 150)
    cart = %CartView{items: [%{product_id: product.id, quantity: 2}]}

    assert {:ok, %{items: [%{product_id: id, quantity: 2, price: 150}], total_amount: 300}} =
             Lines.from_cart(cart)

    assert id == product.id
  end

  test "rejects a cart with an unavailable product" do
    product = insert(:product, is_active: false)
    cart = %CartView{items: [%{product_id: product.id, quantity: 1}]}

    assert {:error, :product_unavailable} = Lines.from_cart(cart)
  end
end
