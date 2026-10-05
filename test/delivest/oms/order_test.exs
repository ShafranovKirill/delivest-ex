defmodule Delivest.Oms.OrderTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Oms.{CartView, Carts, Order, Orders}
  alias Delivest.Repo

  describe "order schema" do
    test "accepts valid pickup order data" do
      attrs = %{
        branch_id: Ecto.UUID.generate(),
        status: :created,
        fulfillment_type: :pickup,
        payment_method: :cash,
        cart_id: Ecto.UUID.generate(),
        customer_phone: "+79991234567",
        customer_name: "Иван",
        total_amount: 500
      }

      assert %Ecto.Changeset{valid?: true} = Order.changeset(%Order{}, attrs)
    end

    test "requires an address when fulfillment type is delivery" do
      attrs = %{
        branch_id: Ecto.UUID.generate(),
        status: :created,
        fulfillment_type: :delivery,
        payment_method: :cash,
        cart_id: Ecto.UUID.generate(),
        customer_phone: "+79991234567",
        customer_name: "Иван"
      }

      changeset = Order.changeset(%Order{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).address
    end

    test "validates phone format" do
      attrs = %{
        branch_id: Ecto.UUID.generate(),
        status: :created,
        fulfillment_type: :pickup,
        payment_method: :cash,
        cart_id: Ecto.UUID.generate(),
        customer_phone: "12345",
        customer_name: "Иван"
      }

      changeset = Order.changeset(%Order{}, attrs)
      refute changeset.valid?
      assert "must be in format +7XXXXXXXXXX" in errors_on(changeset).customer_phone
    end

    test "accepts cook_by as a datetime value" do
      attrs = %{
        branch_id: Ecto.UUID.generate(),
        status: :created,
        fulfillment_type: :pickup,
        payment_method: :cash,
        cart_id: Ecto.UUID.generate(),
        customer_phone: "+79991234567",
        customer_name: "Иван",
        cook_by: ~N[2026-10-05 18:30:00]
      }

      assert %Ecto.Changeset{valid?: true} = Order.changeset(%Order{}, attrs)
    end

    test "accepts cook_by up to 30 days from today" do
      attrs = %{
        branch_id: Ecto.UUID.generate(),
        status: :created,
        fulfillment_type: :pickup,
        payment_method: :cash,
        cart_id: Ecto.UUID.generate(),
        cook_by: NaiveDateTime.new!(Date.add(Date.utc_today(), 30), ~T[23:59:59])
      }

      assert %Ecto.Changeset{valid?: true} = Order.changeset(%Order{}, attrs)
    end

    test "rejects cook_by more than 30 days from today" do
      attrs = %{
        branch_id: Ecto.UUID.generate(),
        status: :created,
        fulfillment_type: :pickup,
        payment_method: :cash,
        cart_id: Ecto.UUID.generate(),
        cook_by: NaiveDateTime.new!(Date.add(Date.utc_today(), 31), ~T[00:00:00])
      }

      changeset = Order.changeset(%Order{}, attrs)

      refute changeset.valid?
      assert "must be no more than 30 days from today" in errors_on(changeset).cook_by
    end
  end

  describe "order context" do
    test "creates an order from a non-empty cart and detaches it" do
      product = insert(:product, price: 175)

      assert {:ok, %CartView{} = cart} =
               Carts.create_cart(%{session_id: "order-cart", branch_id: Ecto.UUID.generate()})

      assert {:ok, _, %CartView{} = populated_cart} = Carts.add_item(cart.id, product.id, 3)

      assert {:ok, %Order{} = order} =
               Orders.create_order(%{
                 "cart_id" => populated_cart.id,
                 "customer_phone" => "+79991234567",
                 "customer_name" => "Иван",
                 "fulfillment_type" => "pickup",
                 "payment_method" => "cash"
               })

      assert order.total_amount == 525
      assert length(order.items) == 1
      assert Enum.at(order.items, 0).product_id == product.id
      assert Enum.at(order.items, 0).quantity == 3
      assert Repo.get!(Delivest.Oms.Cart, cart.id).session_id == nil
      assert Repo.get!(Delivest.Oms.Cart, cart.id).staff_id == nil
    end

    test "rejects an empty cart" do
      assert {:ok, %CartView{} = cart} =
               Carts.create_cart(%{
                 session_id: "empty-order-cart",
                 branch_id: Ecto.UUID.generate()
               })

      assert {:error, :cart, :cart_is_empty} =
               Orders.create_order(%{
                 "cart_id" => cart.id,
                 "customer_phone" => "+79991234567",
                 "customer_name" => "Иван",
                 "fulfillment_type" => "pickup",
                 "payment_method" => "cash"
               })
    end

    test "stores cook_by timestamp when provided by the client" do
      product = insert(:product, price: 150)

      assert {:ok, %CartView{} = cart} =
               Carts.create_cart(%{
                 session_id: "cook-by-order-cart",
                 branch_id: Ecto.UUID.generate()
               })

      assert {:ok, _, %CartView{} = cart} = Carts.add_item(cart.id, product.id, 1)

      assert {:ok, %Order{} = order} =
               Orders.create_order(%{
                 "cart_id" => cart.id,
                 "customer_phone" => "+79991234567",
                 "customer_name" => "Павел",
                 "fulfillment_type" => "pickup",
                 "payment_method" => "cash",
                 "cook_by" => "2026-10-05T18:30"
               })

      assert order.cook_by == ~N[2026-10-05 18:30:00]
    end

    test "updates order values when the cart is changed" do
      product = insert(:product, price: 200)

      assert {:ok, %CartView{} = cart} =
               Carts.create_cart(%{
                 session_id: "update-order-cart",
                 branch_id: Ecto.UUID.generate()
               })

      assert {:ok, _, %CartView{} = cart} = Carts.add_item(cart.id, product.id, 2)

      assert {:ok, %Order{} = order} =
               Orders.create_order(%{
                 "cart_id" => cart.id,
                 "customer_phone" => "+79991234567",
                 "customer_name" => "Анна",
                 "fulfillment_type" => "pickup",
                 "payment_method" => "cash"
               })

      assert {:ok, %Order{} = updated_order} =
               Orders.update_order(order, %{
                 "customer_name" => "Мария",
                 "payment_method" => "card_offline",
                 "cart_id" => cart.id
               })

      assert updated_order.customer_name == "Мария"
      assert updated_order.payment_method == :card_offline
      assert updated_order.total_amount == 400
    end

    test "soft_delete_order marks the order as deleted" do
      product = insert(:product, price: 150)

      assert {:ok, %CartView{} = cart} =
               Carts.create_cart(%{
                 session_id: "delete-order-cart",
                 branch_id: Ecto.UUID.generate()
               })

      assert {:ok, _, %CartView{} = cart} = Carts.add_item(cart.id, product.id, 1)

      assert {:ok, %Order{} = order} =
               Orders.create_order(%{
                 "cart_id" => cart.id,
                 "customer_phone" => "+79991234567",
                 "fulfillment_type" => "pickup",
                 "payment_method" => "cash"
               })

      assert {:ok, %Order{} = deleted_order} = Orders.soft_delete_order(order)
      assert deleted_order.deleted_at != nil
    end

    test "populate_cart_from_order rebuilds the cart from the order items" do
      product = insert(:product, price: 90)

      assert {:ok, %CartView{} = cart} =
               Carts.create_cart(%{session_id: "populate-cart", branch_id: Ecto.UUID.generate()})

      assert {:ok, _, %CartView{} = cart} = Carts.add_item(cart.id, product.id, 2)

      assert {:ok, %Order{} = order} =
               Orders.create_order(%{
                 "cart_id" => cart.id,
                 "customer_phone" => "+79991234567",
                 "customer_name" => "Пётр",
                 "fulfillment_type" => "pickup",
                 "payment_method" => "cash"
               })

      assert {:ok, %CartView{} = restored_cart} =
               Carts.create_cart(%{session_id: "restored", branch_id: Ecto.UUID.generate()})

      assert %CartView{} = Orders.populate_cart_from_order(order, restored_cart.id)

      cart_view = Carts.get_cart_by_id(restored_cart.id)
      assert cart_view.total_quantity == 2
      assert cart_view.total_amount == 180
    end
  end
end
