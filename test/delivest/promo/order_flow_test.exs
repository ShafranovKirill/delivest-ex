defmodule Delivest.Promo.OrderFlowTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Oms
  alias Delivest.Oms.{Carts, Orders}
  alias Delivest.Promo.Redemption

  setup do
    branch = insert(:branch)
    pizza = insert_branch_product(branch.id, slug: "pizza", name: "Pizza", price: 10_000)
    insert_branch_product(branch.id, slug: "cola", name: "Cola", price: 9000)
    %{branch: branch, pizza: pizza}
  end

  defp cart_with(branch, product, quantity) do
    {:ok, cart} =
      Carts.create_cart(%{
        session_id: "s-#{System.unique_integer([:positive])}",
        branch_id: branch.id
      })

    {:ok, _, _} = Carts.add_item(cart.id, product.id, quantity)
    cart
  end

  defp order_attrs(cart, extra \\ %{}) do
    Map.merge(
      %{"cart_id" => cart.id, "branch_id" => cart.branch_id, "fulfillment_type" => "pickup"},
      extra
    )
  end

  test "stores the promotion, prices and a redemption on the order", %{
    branch: branch,
    pizza: pizza
  } do
    promo =
      insert_promotion(branch.id,
        kind: :public_code,
        name: "Summer",
        rules: ~s(then discount 50 rub gift "cola")
      )

    insert_code(promo, code: "SUMMER")
    cart = cart_with(branch, pizza, 3)
    {:ok, _} = Oms.apply_promo_code(cart.id, "summer")

    assert {:ok, order} = Orders.create_order(order_attrs(cart))

    assert order.subtotal_amount == 30_000
    assert order.discount_amount == 5000
    assert order.total_amount == 25_000
    assert [%{name: "Summer", code: "SUMMER", discount: 5000}] = order.promotions

    paid = Enum.reject(order.items, & &1.gift)
    assert Enum.sum(Enum.map(paid, &(&1.price * &1.quantity))) == 25_000
    assert Enum.all?(paid, &(&1.base_price == 10_000))
    assert [%{title: "Cola", price: 0, base_price: 9000}] = Enum.filter(order.items, & &1.gift)

    assert [%Redemption{discount: 5000}] = Repo.all(Redemption)
  end

  test "fails when the global limit is used up", %{branch: branch, pizza: pizza} do
    insert_promotion(branch.id, usage_limit: 1, rules: "then discount 10%")

    assert {:ok, %{total_amount: 9000}} =
             Orders.create_order(order_attrs(cart_with(branch, pizza, 1)))

    assert {:ok, %{total_amount: 10_000, promotions: []}} =
             Orders.create_order(order_attrs(cart_with(branch, pizza, 1)))
  end

  test "a single-use code of an unlimited promotion works once", %{branch: branch, pizza: pizza} do
    promo = insert_promotion(branch.id, kind: :public_code, rules: "then discount 10 rub")
    insert_code(promo, code: "ONE", usage_limit: 1)

    first = cart_with(branch, pizza, 1)
    {:ok, _} = Oms.apply_promo_code(first.id, "one")
    assert {:ok, %{total_amount: 9000}} = Orders.create_order(order_attrs(first))

    second = cart_with(branch, pizza, 1)
    assert {:error, {:promo, :code_used}} = Oms.apply_promo_code(second.id, "one")
  end

  test "refuses a stale price when the client expects less", %{branch: branch, pizza: pizza} do
    cart = cart_with(branch, pizza, 1)

    assert {:error, :pricing, :price_changed} =
             Orders.create_order(order_attrs(cart, %{"expected_total" => 9000}))

    assert {:ok, _order} = Orders.create_order(order_attrs(cart, %{"expected_total" => "10000"}))
  end

  test "applies the per-client limit to the resolved client", %{branch: branch, pizza: pizza} do
    insert_promotion(branch.id, per_client_limit: 1, rules: "then discount 10 rub")
    phone = "+79990001122"

    assert {:ok, %{total_amount: 9000}} =
             Orders.create_order(
               order_attrs(cart_with(branch, pizza, 1), %{"customer_phone" => phone})
             )

    assert {:ok, %{total_amount: 10_000}} =
             Orders.create_order(
               order_attrs(cart_with(branch, pizza, 1), %{"customer_phone" => phone})
             )

    assert {:ok, %{total_amount: 10_000}} =
             Orders.create_order(order_attrs(cart_with(branch, pizza, 1)))
  end

  test "cancelled orders release their redemption", %{branch: branch, pizza: pizza} do
    insert_promotion(branch.id, usage_limit: 1, rules: "then discount 10 rub")

    {:ok, order} = Orders.create_order(order_attrs(cart_with(branch, pizza, 1)))

    {:ok, _} = Orders.cancel_order(order, :system, %{"cancel_reason" => "other"})

    assert {:ok, %{total_amount: 9000}} =
             Orders.create_order(order_attrs(cart_with(branch, pizza, 1)))
  end

  test "editing an order keeps its single-use personal code", %{branch: branch, pizza: pizza} do
    client = insert(:client, phone: "+79995556677")
    promo = insert_promotion(branch.id, kind: :personal_code, rules: "then discount 20 rub")
    insert_code(promo, code: "ONCE", client_id: client.id, usage_limit: 1)

    cart = cart_with(branch, pizza, 1)
    {:ok, _} = Carts.update_context(cart.id, %{client_id: client.id, promo_code: "ONCE"})

    {:ok, order} = Orders.create_order(order_attrs(cart, %{"customer_phone" => client.phone}))
    assert order.total_amount == 8000

    {:ok, draft} = Orders.create_draft_cart(order)
    assert draft.promo_code == "ONCE"

    {:ok, updated} =
      Orders.update_order(order, %{"cart_id" => draft.id, "customer_phone" => client.phone})

    assert updated.total_amount == 8000
    assert [%Redemption{}] = Repo.all(Redemption)
  end

  test "apply_promo_code rejects unusable codes and keeps pending ones", %{
    branch: branch,
    pizza: pizza
  } do
    cart = cart_with(branch, pizza, 1)
    assert {:error, {:promo, :not_found}} = Oms.apply_promo_code(cart.id, "missing")
    assert {:error, {:promo, :not_found}} = Oms.apply_promo_code(cart.id, "  ")

    promo =
      insert_promotion(branch.id,
        kind: :public_code,
        rules: "when subtotal >= 500 then discount 10%"
      )

    insert_code(promo, code: "LATER")

    assert {:ok, %{promo_code: "LATER", code: %{status: :pending}, total_amount: 10_000}} =
             Oms.apply_promo_code(cart.id, "later")

    assert {:ok, %{code: nil, promo_code: nil}} = Oms.remove_promo_code(cart.id)
  end
end
