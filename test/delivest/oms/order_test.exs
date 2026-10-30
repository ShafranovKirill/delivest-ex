defmodule Delivest.Oms.OrderTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory
  import Delivest.OrderFixtures

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

    test "an order on the way keeps its courier fulfillment" do
      delivering = %Order{status: :delivering, fulfillment_type: :delivery, payment_method: :cash}
      changeset = Order.changeset(delivering, %{fulfillment_type: :pickup})
      assert %{fulfillment_type: [_]} = errors_on(changeset)

      ready = %Order{delivering | status: :ready}

      refute Map.has_key?(
               errors_on(Order.changeset(ready, %{fulfillment_type: :pickup})),
               :fulfillment_type
             )
    end

    test "the status is not cast from attrs" do
      changeset = Order.changeset(%Order{}, %{status: :completed})
      assert Ecto.Changeset.get_field(changeset, :status) == :created
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
      assert "must be in E.164 format" in errors_on(changeset).customer_phone
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
        cook_by: ~U[2026-10-05 18:30:00Z]
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
        cook_by: DateTime.new!(Date.add(Date.utc_today(), 30), ~T[23:59:59])
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
        cook_by: DateTime.new!(Date.add(Date.utc_today(), 31), ~T[00:00:00])
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

    test "keeps the customer snapshot when the client renames" do
      product = insert_branch_product(@branch_id, price: 100)
      {:ok, cart} = Carts.create_cart(%{session_id: "snapshot", branch_id: @branch_id})
      {:ok, _, cart} = Carts.add_item(cart.id, product.id, 1)

      assert {:ok, %Order{} = order} =
               Orders.create_order(%{
                 "cart_id" => cart.id,
                 "customer_phone" => "+79991230000",
                 "customer_name" => "Иван",
                 "persons" => 2,
                 "fulfillment_type" => "pickup",
                 "payment_method" => "cash"
               })

      Repo.update_all(Delivest.Identity.Client, set: [name: "Пётр"])
      order = Repo.get!(Order, order.id)

      assert order.customer_name == "Иван"
      assert order.customer_phone == "+79991230000"
      assert order.persons == 2
    end

    test "takes the missing name from the client" do
      client = insert(:client, phone: "+79991230001", name: "Анна")
      product = insert_branch_product(@branch_id, price: 100)
      {:ok, cart} = Carts.create_cart(%{session_id: "snapshot-client", branch_id: @branch_id})
      {:ok, _, cart} = Carts.add_item(cart.id, product.id, 1)

      assert {:ok, %Order{customer_phone: "+79991230001", customer_name: "Анна"}} =
               Orders.create_order(%{
                 "cart_id" => cart.id,
                 "client_id" => client.id,
                 "customer_phone" => client.phone,
                 "fulfillment_type" => "pickup",
                 "payment_method" => "cash"
               })
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

      assert "must be in E.164 format" in errors_on(changeset).customer_phone
    end

    test "rejects orders of a blocked client" do
      insert(:client, phone: "+79995550000", status: :blocked)
      product = insert_branch_product(@branch_id, price: 100)
      {:ok, cart} = Carts.create_cart(%{session_id: "blocked", branch_id: @branch_id})
      {:ok, _, cart} = Carts.add_item(cart.id, product.id, 1)

      assert {:error, :client_id, :client_blocked} =
               Orders.create_order(%{
                 "cart_id" => cart.id,
                 "customer_phone" => "+79995550000",
                 "fulfillment_type" => "pickup",
                 "payment_method" => "cash"
               })

      assert Repo.aggregate(Order, :count) == 0
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

      assert order.cook_by == ~U[2026-10-05 15:30:00Z]
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

    test "update keeps the author and detaches the new cart" do
      staff_id = Ecto.UUID.generate()
      order = order_fixture(@branch_id, attrs: %{"staff_id" => staff_id})
      draft = draft_cart_for(order)

      assert {:ok, %Order{} = updated} =
               Orders.update_order(order, %{"cart_id" => draft.id, "payment_method" => "cash"})

      assert updated.staff_id == staff_id
      assert updated.cart_id == draft.id
      assert Repo.get!(Delivest.Oms.Cart, draft.id).staff_id == nil
    end

    test "update rejects a cart of another order" do
      order = order_fixture(@branch_id)
      other = order_fixture(@branch_id)

      assert {:error, :cart, :cart_already_ordered} =
               Orders.update_order(order, %{"cart_id" => other.cart_id})
    end

    test "update rejects a cart of another branch" do
      order = order_fixture(@branch_id)
      foreign = order_fixture(Ecto.UUID.generate())
      draft = draft_cart_for(foreign)

      assert {:error, :cart, :cart_branch_mismatch} =
               Orders.update_order(order, %{"cart_id" => draft.id})
    end

    test "crm orders cannot be changed" do
      order =
        @branch_id
        |> order_fixture()
        |> Order.crm_changeset(%{provider: "frontpad"})
        |> Repo.update!()

      admin = insert(:staff, role: build(:role, permissions: ["admin"]))

      assert {:error, :editable, :crm_order} =
               Orders.update_order(order, %{"cart_id" => order.cart_id})

      assert {:error, :order_locked} = Orders.advance_order(order, :accepted, {:staff, admin})

      assert {:error, :crm_order} =
               Orders.update_payment_method(order, %{"payment_method" => "card_offline"})
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

    test "numbers orders of a branch day by day" do
      product = insert_branch_product(@branch_id, price: 100)

      numbers =
        for session <- ["day-1", "day-2"] do
          {:ok, cart} = Carts.create_cart(%{session_id: session, branch_id: @branch_id})
          {:ok, _, _} = Carts.add_item(cart.id, product.id, 1)

          {:ok, order} =
            Orders.create_order(%{
              "cart_id" => cart.id,
              "fulfillment_type" => "pickup",
              "payment_method" => "cash"
            })

          {order.daily_number, order.number, order.business_date}
        end

      assert [{1, first, date}, {2, second, date}] = numbers
      assert first =~ ~r/^\d{6}-[A-Z0-9]+-001$/
      assert second =~ ~r/^\d{6}-[A-Z0-9]+-002$/
    end

    test "update_payment_method changes only the payment without a cart" do
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
               Orders.update_payment_method(order, %{
                 "status" => "preparing",
                 "payment_method" => "card_offline",
                 "total_amount" => 1
               })

      assert updated.status == :created
      assert updated.payment_method == :card_offline
      assert updated.total_amount == 240
      assert length(updated.items) == 1
    end

    test "cancelling needs a reason that is dropped when the order comes back" do
      product = insert_branch_product(@branch_id, price: 120)
      {:ok, cart} = Carts.create_cart(%{session_id: "cancel-reason", branch_id: @branch_id})
      {:ok, _, _cart} = Carts.add_item(cart.id, product.id, 1)

      {:ok, order} =
        Orders.create_order(%{
          "cart_id" => cart.id,
          "fulfillment_type" => "pickup",
          "payment_method" => "cash"
        })

      admin = insert(:staff, role: build(:role, permissions: ["admin"]))
      {:ok, order} = Orders.advance_order(order, :accepted, {:staff, admin})

      assert {:error, changeset} = Orders.cancel_order(order, {:staff, admin}, %{})
      assert %{cancel_reason: _} = errors_on(changeset)

      assert {:ok,
              %{status: :cancelled, cancel_reason: :out_of_stock, cancel_note: "Нет сыра"} =
                cancelled} =
               Orders.cancel_order(order, {:staff, admin}, %{
                 "cancel_reason" => "out_of_stock",
                 "cancel_note" => "Нет сыра"
               })

      assert {:error, :order_finished} =
               Orders.update_payment_method(cancelled, %{"payment_method" => "card_offline"})

      assert {:ok, %{status: :accepted, cancel_reason: nil, cancel_note: nil}} =
               Orders.revert_order_status(Repo.reload!(cancelled), admin, "Клиент вернулся")
    end
  end

  defp draft_cart_for(order) do
    {:ok, cart} = Carts.create_cart(%{branch_id: order.branch_id})
    Orders.populate_cart_from_order(order, cart.id)
  end
end
