defmodule Delivest.Promo.FirstOrderConcurrencyTest do
  use ExUnit.Case, async: false

  import Delivest.Factory
  import Ecto.Query

  alias Delivest.Oms.{Cart, Carts, Order, Orders}
  alias Delivest.Promo.PromoCode
  alias Delivest.Repo
  alias Ecto.Adapters.SQL.Sandbox

  test "different public and personal first-order codes race in one branch" do
    run_race(:codes)
  end

  test "two automatic first-order checkouts race in one branch" do
    run_race(:automatic)
  end

  defp run_race(mode) do
    {branch, product, client, promotions, carts} =
      Sandbox.unboxed_run(Repo, fn ->
        branch = insert(:branch)
        product = insert_branch_product(branch.id, slug: "first-#{Ecto.UUID.generate()}")
        client = insert(:client)

        {promotions, codes} =
          case mode do
            :codes ->
              public =
                insert_promotion(branch.id,
                  kind: :public_code,
                  combinable: true,
                  rules: "when first_order then discount 10%"
                )

              personal =
                insert_promotion(branch.id,
                  kind: :personal_code,
                  combinable: true,
                  rules: "when first_order then discount 10%"
                )

              insert_code(public, code: "FIRSTPUBLIC")
              insert_code(personal, code: "FIRSTPERSONAL", client_id: client.id)
              {[public, personal], ["FIRSTPUBLIC", "FIRSTPERSONAL"]}

            :automatic ->
              promotion =
                insert_promotion(branch.id, rules: "when first_order then discount 10%")

              {[promotion], [nil, nil]}
          end

        carts =
          for code <- codes do
            {:ok, cart} = Carts.create_cart(%{branch_id: branch.id})
            {:ok, _, _} = Carts.add_item(cart.id, product.id)

            if code do
              {:ok, _} = Carts.update_context(cart.id, %{client_id: client.id})
              {:ok, _} = Delivest.Oms.apply_promo_code(cart.id, code)
            end

            cart
          end

        {branch, product, client, promotions, carts}
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

      order_ids = Enum.map(results, fn {:ok, order} -> order.id end)

      assert Sandbox.unboxed_run(Repo, fn ->
               Repo.aggregate(
                 from(r in Delivest.Promo.Redemption, where: r.order_id in ^order_ids),
                 :count
               )
             end) == 1
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
        promotion_ids = Enum.map(promotions, & &1.id)
        Repo.delete_all(from c in PromoCode, where: c.promotion_id in ^promotion_ids)
        Enum.each(promotions, &Repo.delete!/1)

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
