defmodule Delivest.Oms.Orders.LinesTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Oms.Orders.Lines
  alias Delivest.Promo.{Line, Result}

  test "builds order lines and total from the pricing" do
    product = insert(:product, price: 150)
    line = %Line{product_id: product.id, base_price: 150, quantity: 2, total: 300}

    assert {:ok, %{items: [%{product_id: id, quantity: 2, price: 150}], total_amount: 300}} =
             Lines.from_pricing(%Result{lines: [line], total: 300})

    assert id == product.id
  end

  test "splits a discounted line into integer unit prices" do
    product = insert(:product, price: 100)
    line = %Line{product_id: product.id, base_price: 100, quantity: 3, total: 250}

    assert {:ok, %{items: items}} = Lines.from_pricing(%Result{lines: [line], total: 250})

    assert [%{price: 84, quantity: 1, base_price: 100}, %{price: 83, quantity: 2}] = items
    assert Enum.sum(Enum.map(items, &(&1.price * &1.quantity))) == 250
  end

  test "keeps gifts as free lines" do
    product = insert(:product, price: 90)
    line = %Line{product_id: product.id, base_price: 90, quantity: 1, total: 0, gift: true}

    assert {:ok, %{items: [%{price: 0, base_price: 90, gift: true}], total_amount: 0}} =
             Lines.from_pricing(%Result{lines: [line], total: 0})
  end

  test "rejects a cart with an unavailable product" do
    product = insert(:product, is_active: false)
    line = %Line{product_id: product.id, base_price: 100, quantity: 1, total: 100}

    assert {:error, :product_unavailable} = Lines.from_pricing(%Result{lines: [line], total: 100})
  end
end
