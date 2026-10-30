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

    client = insert(:client)
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
end
