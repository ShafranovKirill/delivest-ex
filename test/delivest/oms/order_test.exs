defmodule Delivest.Oms.OrderTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  @branch_id "00000000-0000-4000-8000-000000000001"

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
      product = insert_branch_product(@branch_id, price: 175)

      assert {:ok, %CartView{} = cart} =
               Carts.create_cart(%{session_id: "order-cart", branch_id: @branch_id})

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

    test "treats a bare phone prefix as no phone" do
      product = insert_branch_product(@branch_id, price: 100)
      {:ok, cart} = Carts.create_cart(%{session_id: "bare-phone", branch_id: @branch_id})
      {:ok, _, cart} = Carts.add_item(cart.id, product.id, 1)

      assert {:ok, %Order{client_id: nil}} =
               Orders.create_order(%{
                 "cart_id" => cart.id,
                 "customer_phone" => "+7",
                 "fulfillment_type" => "pickup",
                 "payment_method" => "cash"
               })
    end

    test "reports an invalid phone as an order error" do
      product = insert_branch_product(@branch_id, price: 100)
      {:ok, cart} = Carts.create_cart(%{session_id: "invalid-phone", branch_id: @branch_id})
      {:ok, _, cart} = Carts.add_item(cart.id, product.id, 1)

      assert {:error, :order, %Ecto.Changeset{data: %Order{}} = changeset} =
               Orders.create_order(%{
                 "cart_id" => cart.id,
                 "customer_phone" => "+7999",
                 "fulfillment_type" => "pickup",
                 "payment_method" => "cash"
               })

      assert "must be in format +7XXXXXXXXXX" in errors_on(changeset).customer_phone
    end

    test "rejects a cart with a product disabled after it was added" do
      product = insert_branch_product(@branch_id, price: 100)
      {:ok, cart} = Carts.create_cart(%{session_id: "disabled-product", branch_id: @branch_id})
      {:ok, _, cart} = Carts.add_item(cart.id, product.id, 1)

      product |> Ecto.Changeset.change(is_active: false) |> Repo.update!()

      assert {:error, :products, :product_unavailable} =
               Orders.create_order(%{
                 "cart_id" => cart.id,
                 "fulfillment_type" => "pickup",
                 "payment_method" => "cash"
               })
    end

    test "rejects an empty cart" do
      assert {:ok, %CartView{} = cart} =
               Carts.create_cart(%{
                 session_id: "empty-order-cart",
                 branch_id: @branch_id
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
      product = insert_branch_product(@branch_id, price: 150)

      assert {:ok, %CartView{} = cart} =
               Carts.create_cart(%{
                 session_id: "cook-by-order-cart",
                 branch_id: @branch_id
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
      product = insert_branch_product(@branch_id, price: 200)

      assert {:ok, %CartView{} = cart} =
               Carts.create_cart(%{
                 session_id: "update-order-cart",
                 branch_id: @branch_id
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
      product = insert_branch_product(@branch_id, price: 150)

      assert {:ok, %CartView{} = cart} =
               Carts.create_cart(%{
                 session_id: "delete-order-cart",
                 branch_id: @branch_id
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
      product = insert_branch_product(@branch_id, price: 90)

      assert {:ok, %CartView{} = cart} =
               Carts.create_cart(%{session_id: "populate-cart", branch_id: @branch_id})

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
               Carts.create_cart(%{session_id: "restored", branch_id: @branch_id})

      assert %CartView{} = Orders.populate_cart_from_order(order, restored_cart.id)

      cart_view = Carts.get_cart_by_id(restored_cart.id)
      assert cart_view.total_quantity == 2
      assert cart_view.total_amount == 180
    end

    test "does not create a second order from the same cart" do
      product = insert_branch_product(@branch_id, price: 100)

      {:ok, cart} = Carts.create_cart(%{session_id: "double-order", branch_id: @branch_id})
      {:ok, _, cart} = Carts.add_item(cart.id, product.id, 1)

      attrs = %{"cart_id" => cart.id, "fulfillment_type" => "pickup", "payment_method" => "cash"}

      assert {:ok, %Order{}} = Orders.create_order(attrs)
      assert {:error, :cart, :cart_already_ordered} = Orders.create_order(attrs)
    end

    test "rejects a cart that belongs to another branch" do
      product = insert_branch_product(@branch_id, price: 100)

      {:ok, cart} = Carts.create_cart(%{session_id: "branch-mismatch", branch_id: @branch_id})
      {:ok, _, cart} = Carts.add_item(cart.id, product.id, 1)

      assert {:error, :cart, :cart_branch_mismatch} =
               Orders.create_order(%{
                 "cart_id" => cart.id,
                 "branch_id" => Ecto.UUID.generate(),
                 "fulfillment_type" => "pickup",
                 "payment_method" => "cash"
               })
    end

    test "allows repeated order numbers once the number sequence wraps around" do
      product = insert_branch_product(@branch_id, price: 100)

      for session <- ["wrap-1", "wrap-2"] do
        {:ok, cart} = Carts.create_cart(%{session_id: session, branch_id: @branch_id})
        {:ok, _, _} = Carts.add_item(cart.id, product.id, 1)

        {:ok, order} =
          Orders.create_order(%{
            "cart_id" => cart.id,
            "fulfillment_type" => "pickup",
            "payment_method" => "cash"
          })

        order |> Ecto.Changeset.change(number: "A000") |> Repo.update!()
      end

      assert Repo.aggregate(from(o in Order, where: o.number == "A000"), :count) == 2
    end

    test "update_order_details changes status and payment without a cart" do
      product = insert_branch_product(@branch_id, price: 120)

      {:ok, cart} = Carts.create_cart(%{session_id: "details-update", branch_id: @branch_id})
      {:ok, _, cart} = Carts.add_item(cart.id, product.id, 2)

      {:ok, order} =
        Orders.create_order(%{
          "cart_id" => cart.id,
          "fulfillment_type" => "pickup",
          "payment_method" => "cash"
        })

      assert {:ok, updated} =
               Orders.update_order_details(order, %{
                 "status" => "preparing",
                 "payment_method" => "card_offline",
                 "total_amount" => 1
               })

      assert updated.status == :preparing
      assert updated.payment_method == :card_offline
      assert updated.total_amount == 240
      assert length(updated.items) == 1
    end

    test "Frontpad orders enqueue their CRM job in the same transaction" do
      branch = insert(:branch, is_active: true)

      Repo.insert!(%Delivest.Identity.Branch.BranchInfo{
        branch_id: branch.id,
        frontpad_enabled: true,
        frontpad_api_key: "key"
      })

      product = insert_branch_product(branch.id, price: 100)
      {:ok, cart} = Carts.create_cart(%{session_id: "frontpad", branch_id: branch.id})
      {:ok, _, _} = Carts.add_item(cart.id, product.id, 1)

      assert {:ok, %Order{status: :crm} = order} =
               Delivest.Oms.create_order(%{
                 "cart_id" => cart.id,
                 "branch_id" => branch.id,
                 "fulfillment_type" => "pickup",
                 "payment_method" => "cash"
               })

      assert [%Oban.Job{args: %{"order_id" => order_id}}] = Repo.all(Oban.Job)
      assert order_id == order.id
    end
  end
end
