defmodule Delivest.LoyaltyTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Identity.Branch.{BranchInfo, LoyaltySettings}
  alias Delivest.Loyalty
  alias Delivest.Loyalty.Entry
  alias Delivest.Oms.Orders

  setup do
    branch = insert(:branch)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      loyalty: %LoyaltySettings{enabled: true, per_rubles: 100, stars: 5, expire_days: 180}
    })

    client = insert(:client, phone: "+79990001122")
    manager = insert(:staff, role: build(:role, permissions: ["orders.update", "clients.update"]))
    insert(:staff_branch, staff: manager, branch: branch)
    manager = Repo.preload(manager, [:role, :branches])

    %{branch: branch, client: client, manager: manager}
  end

  defp order(%{branch: branch, client: client}, price \\ 25_000) do
    branch.id
    |> order_fixture(price: price)
    |> Ecto.Changeset.change(client_id: client.id, fulfillment_type: :pickup)
    |> Repo.update!()
  end

  defp update_info(branch, changes) do
    BranchInfo
    |> Repo.get_by!(branch_id: branch.id)
    |> BranchInfo.changeset(changes)
    |> Repo.update!()

    Cachex.clear(:branch_cache)
  end

  defp finish(order, manager, to) do
    steps = [:accepted, :preparing, :ready, :completed]

    order =
      steps
      |> Enum.take_while(&(&1 != to))
      |> Kernel.++([to])
      |> Enum.uniq()
      |> Enum.reduce(order, fn status, acc ->
        {:ok, acc} = Orders.advance_order(acc, status, {:staff, manager})
        Repo.reload!(acc)
      end)

    deliver_events()
    order
  end

  test "stars come from the order total below the delivery, rounded down", ctx do
    order = %{order(ctx, 25_050) | delivery_amount: 0}
    settings = Loyalty.settings(ctx.branch)

    assert Loyalty.stars_for(order, settings) == 10
    assert Loyalty.stars_for(%{order | delivery_amount: 15_000}, settings) == 5
  end

  test "completing an order credits the client once", ctx do
    order = order(ctx) |> finish(ctx.manager, :completed)

    assert Loyalty.balance(ctx.client.id) == 10
    assert {:ok, nil} = Loyalty.accrue(order)
    assert Loyalty.balance(ctx.client.id) == 10
    assert [%Entry{kind: :accrual, amount: 10}] = Loyalty.history(ctx.client.id)
  end

  test "nothing is credited when the program is off", ctx do
    update_info(ctx.branch, %{"loyalty" => %{"enabled" => false}})
    order(ctx) |> finish(ctx.manager, :completed)

    assert Loyalty.balance(ctx.client.id) == 0
  end

  test "an order run by the crm is not credited", ctx do
    update_info(ctx.branch, %{
      "crm" => %{
        "enabled" => true,
        "provider" => "frontpad",
        "frontpad" => %{"api_key" => "key"}
      }
    })

    refute Loyalty.enabled?(ctx.branch.id)
  end

  test "cancelling an order after it was credited takes the stars back, never below zero",
       ctx do
    order = order(ctx) |> finish(ctx.manager, :completed)
    Repo.insert!(%Entry{client_id: ctx.client.id, kind: :adjust, amount: 0})
    Repo.update_all(Delivest.Loyalty.Account, set: [balance: 4])

    assert {:ok, %Entry{kind: :accrual_reversal, amount: -4}} = Loyalty.reverse(order)
    assert Loyalty.balance(ctx.client.id) == 0
    assert {:ok, nil} = Loyalty.reverse(order)
  end

  test "a manager corrects the balance with a reason and cannot take more than there is", ctx do
    assert {:error, :reason_required} =
             Loyalty.adjust(ctx.manager, ctx.branch, ctx.client.id, 50, " ")

    assert {:ok, %Entry{amount: 50}} =
             Loyalty.adjust(ctx.manager, ctx.branch, ctx.client.id, 50, "gift")

    assert {:ok, %Entry{amount: -50}} =
             Loyalty.adjust(ctx.manager, ctx.branch, ctx.client.id, -80, "fix")

    assert Loyalty.balance(ctx.client.id) == 0
  end

  test "stars expire in the order they were credited", ctx do
    order(ctx) |> finish(ctx.manager, :completed)
    later = DateTime.add(DateTime.utc_now(), 181, :day)

    assert Loyalty.expire_due() == 0
    assert Loyalty.expire_due(later) == 10
    assert Loyalty.balance(ctx.client.id) == 0
    assert Loyalty.expire_due(later) == 0
    assert Enum.any?(Loyalty.history(ctx.client.id), &(&1.kind == :expire and &1.amount == -10))
  end

  test "the summary adds up what was issued and what is still owed", ctx do
    order(ctx) |> finish(ctx.manager, :completed)
    {:ok, _} = Loyalty.adjust(ctx.manager, ctx.branch, ctx.client.id, 5, "gift")

    assert %{issued: 15, liability: 15, expired: 0, reversed: 0} = Loyalty.summary(ctx.branch.id)
  end

  describe "paying with stars" do
    setup ctx do
      update_info(ctx.branch, %{"loyalty" => %{"spend_enabled" => true, "max_percent" => 50}})
      {:ok, _} = Loyalty.adjust(ctx.manager, ctx.branch, ctx.client.id, 100, "welcome")
      :ok
    end

    defp place(ctx, stars, price \\ 30_000) do
      product = insert_branch_product(ctx.branch.id, price: price)

      {:ok, cart} =
        Delivest.Oms.Carts.create_cart(%{
          session_id: Ecto.UUID.generate(),
          branch_id: ctx.branch.id
        })

      {:ok, _, _} = Delivest.Oms.Carts.add_item(cart.id, product.id, 1)

      Orders.create_order(%{
        "cart_id" => cart.id,
        "branch_id" => ctx.branch.id,
        "customer_phone" => ctx.client.phone,
        "fulfillment_type" => "pickup",
        "payment_method" => "cash",
        "spend_points" => stars
      })
    end

    test "takes stars off the total and the balance, in the items too", ctx do
      assert {:ok, order} = place(ctx, 100)

      assert order.points_spent == 100
      assert order.total_amount == 20_000
      assert order.discount_amount == 10_000
      assert Loyalty.balance(ctx.client.id) == 0
      order = Repo.preload(order, :items, force: true)
      assert Enum.sum(Enum.map(order.items, &(&1.price * &1.quantity))) == 20_000
    end

    test "refuses more than the share of the order allows", ctx do
      {:ok, _} = Loyalty.adjust(ctx.manager, ctx.branch, ctx.client.id, 100, "more")
      assert {:error, _step, :points_over_limit} = place(ctx, 160)
      assert Loyalty.balance(ctx.client.id) == 200
    end

    test "refuses more than the balance", ctx do
      assert {:error, _step, :insufficient_points} = place(ctx, 101, 100_000)
    end

    test "refuses when spending is off", ctx do
      update_info(ctx.branch, %{"loyalty" => %{"spend_enabled" => false}})
      assert {:error, _step, :points_unavailable} = place(ctx, 10)
    end

    test "can pay the whole order when the share is 100", ctx do
      update_info(ctx.branch, %{"loyalty" => %{"max_percent" => 100}})
      assert {:ok, order} = place(ctx, 100, 10_000)
      assert order.total_amount == 0

      order = finish(order, ctx.manager, :completed)
      assert order.status == :completed
      assert Delivest.Fiscal.list(order.id) == []
    end

    test "cancelling gives the stars back once", ctx do
      {:ok, order} = place(ctx, 100)

      {:ok, order} =
        Orders.cancel_order(order, {:staff, ctx.manager}, %{"cancel_reason" => "client"})

      deliver_events()

      assert Loyalty.balance(ctx.client.id) == 100
      assert {:ok, nil} = Loyalty.refund(order)
      assert Loyalty.balance(ctx.client.id) == 100
    end

    test "completing credits stars only for the part paid with money", ctx do
      {:ok, order} = place(ctx, 100, 50_000)
      finish(order, ctx.manager, :completed)

      assert Loyalty.balance(ctx.client.id) == 20
    end

    test "editing the items of such an order is closed", ctx do
      {:ok, order} = place(ctx, 100)
      assert {:error, :with_points} = Delivest.Oms.OrderLock.check(order, :items)
    end
  end
end
