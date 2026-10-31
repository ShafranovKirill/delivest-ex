defmodule Delivest.Loyalty.RewardsTest do
  use Delivest.DataCase, async: true
  import Delivest.Factory
  alias Delivest.Identity.Branch.{BranchInfo, LoyaltySettings}
  alias Delivest.Oms.{Carts, Orders}
  alias Delivest.Loyalty

  setup do
    branch = insert(:branch)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      loyalty: %LoyaltySettings{enabled: true, shop_enabled: true}
    })

    client = insert(:client, phone: "+79991234567")

    staff =
      insert(:staff,
        role: build(:role, permissions: ["clients.update", "orders.update"]),
        branches: [branch]
      )

    {:ok, _} = Loyalty.adjust(staff, branch, client.id, 100, "gift")
    product = insert_branch_product(branch.id, price: 20000, stars_price: 40)
    {:ok, cart} = Carts.create_cart(%{session_id: Ecto.UUID.generate(), branch_id: branch.id})
    %{branch: branch, client: client, product: product, cart: cart, staff: staff}
  end

  defp place(ctx) do
    Orders.create_order(%{
      "cart_id" => ctx.cart.id,
      "branch_id" => ctx.branch.id,
      "customer_phone" => ctx.client.phone,
      "fulfillment_type" => "pickup",
      "payment_method" => "cash"
    })
  end

  test "reward is free in rubles and debits its star price", ctx do
    {:ok, _, cart} = Carts.add_star_item(ctx.cart.id, ctx.product.id, 2)
    assert cart.total_amount == 0
    assert length(cart.items) == 1
    assert {:ok, order} = place(ctx)
    assert order.points_spent == 80
    assert order.total_amount == 0
    assert order.discount_amount == 40000
    assert Loyalty.balance(ctx.client.id) == 20
    assert [%{price: 0, stars_spent: 40, quantity: 2}] = Repo.preload(order, :items).items
    {:ok, order} = Orders.cancel_order(order, {:staff, ctx.staff}, %{"cancel_reason" => "client"})
    deliver_events()
    assert Loyalty.balance(ctx.client.id) == 100
    assert {:ok, nil} = Loyalty.refund(order)
  end

  test "balance is checked across all reward units at checkout", ctx do
    {:ok, _, _} = Carts.add_star_item(ctx.cart.id, ctx.product.id, 3)
    assert {:error, :pricing, :insufficient_points} = place(ctx)
    assert Loyalty.balance(ctx.client.id) == 100
  end

  test "paid and reward versions of one product remain separate", ctx do
    {:ok, _, _} = Carts.add_item(ctx.cart.id, ctx.product.id)
    {:ok, _, cart} = Carts.add_star_item(ctx.cart.id, ctx.product.id)
    assert length(cart.items) == 2
    assert {:ok, order} = place(ctx)
    assert order.total_amount == 20000
    assert order.points_spent == 40
  end

  test "checkout uses the current reward price", ctx do
    {:ok, _, _} = Carts.add_star_item(ctx.cart.id, ctx.product.id)
    ctx.product |> Ecto.Changeset.change(stars_price: 120) |> Repo.update!()
    assert {:error, :pricing, :insufficient_points} = place(ctx)
    assert Loyalty.balance(ctx.client.id) == 100
  end

  test "turning off the shop rejects rewards already in a cart", ctx do
    {:ok, _, _} = Carts.add_star_item(ctx.cart.id, ctx.product.id)

    Repo.get_by!(BranchInfo, branch_id: ctx.branch.id)
    |> BranchInfo.changeset(%{"loyalty" => %{"shop_enabled" => false}})
    |> Repo.update!()

    Cachex.clear(:branch_cache)
    assert {:error, :pricing, :points_unavailable} = place(ctx)
    assert Loyalty.balance(ctx.client.id) == 100
  end
end
