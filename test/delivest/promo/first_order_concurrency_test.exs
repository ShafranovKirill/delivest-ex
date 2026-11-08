defmodule Delivest.Promo.FirstOrderConcurrencyTest do
  use ExUnit.Case, async: false

  import Delivest.Factory
  import Ecto.Query

  alias Delivest.Oms.{Cart, Carts, Order, Orders}
  alias Delivest.Repo
  alias Ecto.Adapters.SQL.Sandbox

  test "two website checkouts on separate connections grant first-order discount once" do
    {branch, product, client, promotion, carts} =
      Sandbox.unboxed_run(Repo, fn ->
        branch = insert(:branch)
        product = insert_branch_product(branch.id, slug: "first-#{Ecto.UUID.generate()}")
        client = insert(:client)
        promotion = insert_promotion(branch.id, rules: "when first_order then discount 10%")

        carts =
          for _ <- 1..2 do
            {:ok, cart} = Carts.create_cart(%{branch_id: branch.id})
            {:ok, _, _} = Carts.add_item(cart.id, product.id)
            cart
          end

        {branch, product, client, promotion, carts}
      end)

    try do
      tasks =
        for cart <- carts do
          Task.async(fn ->
            receive do
              :checkout ->
                Sandbox.unboxed_run(Repo, fn ->
                  Orders.create_order(
                    %{
                      "cart_id" => cart.id,
                      "branch_id" => branch.id,
                      "customer_phone" => client.phone,
                      "fulfillment_type" => "pickup"
                    },
                    authenticated_client_id: client.id
                  )
                end)
            end
          end)
        end

      Enum.each(tasks, &send(&1.pid, :checkout))
      results = Task.await_many(tasks, 15_000)
      assert Enum.all?(results, &match?({:ok, %Order{}}, &1))

      assert Enum.sort(Enum.map(results, fn {:ok, order} -> order.total_amount end)) ==
               [9000, 10_000]
    after
      Sandbox.unboxed_run(Repo, fn ->
        cart_ids = Enum.map(carts, & &1.id)
        order_ids = Repo.all(from o in Order, where: o.cart_id in ^cart_ids, select: o.id)

        for id <- order_ids do
          Repo.query!(
            "DELETE FROM oban_jobs WHERE args->>'event_id' IN (SELECT id::text FROM domain_events WHERE aggregate_id = $1)",
            [Ecto.UUID.dump!(id)]
          )

          Repo.query!("DELETE FROM domain_events WHERE aggregate_id = $1", [Ecto.UUID.dump!(id)])
          Repo.query!("DELETE FROM audit_events WHERE subject_id = $1", [id])
        end

        Repo.delete_all(from o in Order, where: o.id in ^order_ids)

        Repo.query!("DELETE FROM order_counters WHERE branch_id = $1", [
          Ecto.UUID.dump!(branch.id)
        ])

        Repo.delete_all(from c in Cart, where: c.id in ^cart_ids)
        Repo.delete!(promotion)

        Repo.delete_all(
          from r in Delivest.Relations.EntityRelation,
            where: r.from_id == ^branch.id or r.to_id == ^product.id
        )

        Repo.delete!(product)
        Repo.delete!(client)
        Repo.delete!(branch)
      end)

      Enum.each(carts, &Cachex.del(:cart_cache, &1.id))
      Sandbox.unboxed_run(Repo, fn -> Delivest.Promo.Catalog.invalidate(branch.id) end)
    end
  end
end
