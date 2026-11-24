defmodule Delivest.Loyalty.SpendConcurrencyTest do
  use ExUnit.Case, async: false

  import Delivest.Factory
  import Ecto.Query

  alias Delivest.Loyalty
  alias Delivest.Loyalty.{Account, Entry}
  alias Delivest.Identity.Branch.{BranchInfo, LoyaltySettings}
  alias Delivest.Oms.{Cart, Carts, Order}
  alias Delivest.Repo
  alias Ecto.Adapters.SQL.Sandbox

  test "two orders cannot spend the same loyalty balance" do
    {branch, client, carts, orders} =
      Sandbox.unboxed_run(Repo, fn ->
        branch = insert(:branch)

        Repo.insert!(%BranchInfo{
          branch_id: branch.id,
          loyalty: %LoyaltySettings{enabled: true, spend_enabled: true}
        })

        client = insert(:client)
        Repo.insert!(%Account{client_id: client.id, balance: 100})

        Repo.insert!(%Entry{
          client_id: client.id,
          branch_id: branch.id,
          kind: :adjust,
          amount: 100,
          remaining: 100,
          expires_at: DateTime.add(DateTime.utc_now(:second), 1, :day),
          reason: "test"
        })

        carts =
          for _ <- 1..2 do
            {:ok, cart} =
              Carts.create_cart(%{branch_id: branch.id, session_id: Ecto.UUID.generate()})

            cart
          end

        orders =
          for {cart, daily_number} <- Enum.with_index(carts, 1) do
            Repo.insert!(%Order{
              number: "SPEND-#{System.unique_integer([:positive])}",
              daily_number: daily_number,
              business_date: Date.utc_today(),
              branch_id: branch.id,
              cart_id: cart.id,
              client_id: client.id,
              points_spent: 80
            })
          end

        {branch, client, carts, orders}
      end)

    try do
      tasks =
        for order <- orders do
          Task.async(fn ->
            receive do
              :spend -> Sandbox.unboxed_run(Repo, fn -> Loyalty.spend(order) end)
            end
          end)
        end

      Enum.each(tasks, &send(&1.pid, :spend))
      results = Task.await_many(tasks, 10_000)

      assert Enum.count(results, &match?({:ok, %Entry{}}, &1)) == 1
      assert Enum.count(results, &(&1 == {:error, :insufficient_points})) == 1

      Sandbox.unboxed_run(Repo, fn ->
        assert Loyalty.balance(client.id) == 20

        assert Repo.aggregate(
                 from(e in Entry, where: e.client_id == ^client.id and e.kind == :redeem),
                 :count
               ) == 1
      end)
    after
      Sandbox.unboxed_run(Repo, fn ->
        Repo.delete_all(from e in Entry, where: e.client_id == ^client.id)
        Repo.delete_all(from o in Order, where: o.id in ^Enum.map(orders, & &1.id))
        Repo.delete_all(from c in Cart, where: c.id in ^Enum.map(carts, & &1.id))
        Repo.delete_all(from a in Account, where: a.client_id == ^client.id)
        Repo.delete!(client)
        Repo.delete_all(from info in BranchInfo, where: info.branch_id == ^branch.id)
        Repo.delete!(branch)
      end)

      Enum.each(carts, &Cachex.del(:cart_cache, &1.id))
    end
  end
end
