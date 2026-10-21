defmodule Delivest.Oms.CartTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  @branch_id "00000000-0000-4000-8000-000000000001"

  alias Delivest.Oms.{Cart, CartItem, CartView, Carts}

  describe "cart schema" do
    test "accepts valid attributes" do
      attrs = %{
        session_id: "session-123",
        branch_id: Ecto.UUID.generate()
      }

      assert %Ecto.Changeset{valid?: true} = Cart.changeset(%Cart{}, attrs)
    end

    test "rejects non-positive quantity" do
      attrs = %{
        cart_id: Ecto.UUID.generate(),
        product_id: Ecto.UUID.generate(),
        quantity: 0
      }

      changeset = CartItem.changeset(%CartItem{}, attrs)
      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).quantity
    end
  end

  describe "cart context" do
    test "creates a cart and calculates totals" do
      product = insert_branch_product(@branch_id, price: 250)

      assert {:ok, %CartView{} = cart} =
               Carts.create_cart(%{session_id: "session-cart", branch_id: @branch_id})

      assert cart.total_quantity == 0
      assert cart.items == []

      assert {:ok, _item, %CartView{} = updated_cart} = Carts.add_item(cart.id, product.id, 2)
      assert updated_cart.total_quantity == 2
      assert updated_cart.total_amount == 500

      assert [%{product_id: product_id, quantity: 2, total_price: 500}] = updated_cart.items
      assert product_id == product.id
    end

    test "adds quantity to existing product instead of duplicating item" do
      product = insert_branch_product(@branch_id, price: 100)

      assert {:ok, %CartView{} = cart} =
               Carts.create_cart(%{session_id: "session-merge", branch_id: @branch_id})

      assert {:ok, _, %CartView{} = first} = Carts.add_item(cart.id, product.id, 1)
      assert {:ok, _, %CartView{} = second} = Carts.add_item(cart.id, product.id, 2)

      assert first.total_quantity == 1
      assert second.total_quantity == 3
      assert [%{quantity: 3, total_price: 300}] = second.items
    end

    test "decrements quantity and removes item when it reaches zero" do
      product = insert_branch_product(@branch_id, price: 80)

      assert {:ok, %CartView{} = cart} =
               Carts.create_cart(%{session_id: "session-clear", branch_id: @branch_id})

      assert {:ok, _, %CartView{} = cart_with_item} = Carts.add_item(cart.id, product.id, 2)
      assert cart_with_item.total_quantity == 2

      assert {:ok, :updated, %CartView{} = updated_cart} = Carts.remove_item(cart.id, product.id)
      assert updated_cart.total_quantity == 1
      assert hd(updated_cart.items).quantity == 1

      assert {:ok, :deleted, %CartView{} = cleared_cart} = Carts.remove_item(cart.id, product.id)
      assert cleared_cart.items == []
      assert cleared_cart.total_quantity == 0
      assert cleared_cart.total_amount == 0
    end

    test "clear_cart removes all cart items and refreshes totals" do
      product_one = insert_branch_product(@branch_id, price: 120)
      product_two = insert_branch_product(@branch_id, price: 80)

      assert {:ok, %CartView{} = cart} =
               Carts.create_cart(%{
                 session_id: "session-clear-all",
                 branch_id: @branch_id
               })

      assert {:ok, _, _} = Carts.add_item(cart.id, product_one.id, 1)
      assert {:ok, _, _} = Carts.add_item(cart.id, product_two.id, 2)

      assert {:ok, %CartView{items: items}} = Carts.clear_cart(cart.id)
      assert items == []
    end

    test "detach_cart removes session and staff attachment from the cart" do
      assert {:ok, %CartView{} = cart} =
               Carts.create_cart(%{
                 session_id: "session-detach",
                 staff_id: Ecto.UUID.generate(),
                 branch_id: @branch_id
               })

      assert {:ok, %CartView{} = detached_cart} = Carts.detach_cart(cart.id)
      assert detached_cart.session_id == nil
      assert detached_cart.staff_id == nil
    end

    test "rejects products of another branch and inactive products" do
      foreign = insert_branch_product(Ecto.UUID.generate(), price: 100)
      inactive = insert_branch_product(@branch_id, price: 100, is_active: false)

      {:ok, cart} = Carts.create_cart(%{session_id: "foreign-product", branch_id: @branch_id})

      assert {:error, :product_unavailable} = Carts.add_item(cart.id, foreign.id, 1)
      assert {:error, :product_unavailable} = Carts.add_item(cart.id, inactive.id, 1)
      assert {:error, :product_unavailable} = Carts.add_item(cart.id, "not-a-uuid", 1)
    end

    test "limits the quantity of a single product" do
      product = insert_branch_product(@branch_id, price: 10)
      {:ok, cart} = Carts.create_cart(%{session_id: "quantity-limit", branch_id: @branch_id})

      assert {:error, :quantity_limit_exceeded} = Carts.add_item(cart.id, product.id, 100)
      assert {:ok, _, _} = Carts.add_item(cart.id, product.id, 99)
      assert {:error, :quantity_limit_exceeded} = Carts.add_item(cart.id, product.id, 1)
    end

    test "owned_by_session? only matches the owning session" do
      {:ok, cart} = Carts.create_cart(%{session_id: "owner", branch_id: @branch_id})

      assert Carts.owned_by_session?(cart.id, "owner")
      refute Carts.owned_by_session?(cart.id, "stranger")
      refute Carts.owned_by_session?(cart.id, nil)
      refute Carts.owned_by_session?("not-a-uuid", "owner")
    end

    test "returns one cart when a session has duplicate carts for a branch" do
      {:ok, _first} = Carts.create_cart(%{session_id: "duplicated", branch_id: @branch_id})
      {:ok, _second} = Carts.create_cart(%{session_id: "duplicated", branch_id: @branch_id})

      assert %CartView{} = Carts.get_cart(session_id: "duplicated", branch_id: @branch_id)
      assert %CartView{} = Carts.get_cart(session_id: "duplicated")
    end
  end
end
