defmodule Delivest.Promo.GiftConcurrencyTest do
  use ExUnit.Case, async: false
  import Delivest.Factory
  import Ecto.Query
  alias Delivest.{Oms, Repo}
  alias Delivest.Oms.{Cart, Carts}
  alias Ecto.Adapters.SQL.Sandbox

  test "concurrent choices use committed rows and retain both promotion keys" do
    {branch, product, first, second, cart} =
      Sandbox.unboxed_run(Repo, fn ->
        branch = insert(:branch)
        product = insert_branch_product(branch.id, slug: "gift-#{Ecto.UUID.generate()}")
        rules = ~s|then gift ("#{product.slug}") x1|
        first = insert_promotion(branch.id, combinable: true, rules: rules)
        second = insert_promotion(branch.id, combinable: true, rules: rules)
        {:ok, cart} = Carts.create_cart(%{branch_id: branch.id})
        {:ok, _, _} = Carts.add_item(cart.id, product.id)
        {branch, product, first, second, cart}
      end)

    try do
      tasks =
        for promotion <- [first, second] do
          Task.async(fn ->
            receive do
              :choose ->
                Sandbox.unboxed_run(Repo, fn ->
                  Oms.choose_promotion_gifts(cart.id, promotion.id, [product.id])
                end)
            end
          end)
        end

      Enum.each(tasks, &send(&1.pid, :choose))
      assert Enum.all?(Task.await_many(tasks), &match?({:ok, _}, &1))

      Sandbox.unboxed_run(Repo, fn ->
        expected = %{first.id => [product.id], second.id => [product.id]}
        assert Repo.get!(Cart, cart.id).promo_gifts == expected
        assert Carts.get_cart_by_id(cart.id).promo_gifts == expected
      end)
    after
      Sandbox.unboxed_run(Repo, fn ->
        Repo.delete_all(from c in Cart, where: c.id == ^cart.id)
        Repo.delete!(first)
        Repo.delete!(second)

        Repo.delete_all(
          from r in Delivest.Relations.EntityRelation, where: r.from_id == ^branch.id
        )

        Repo.delete!(product)
        Repo.delete!(branch)
      end)

      Cachex.del(:cart_cache, cart.id)
      Sandbox.unboxed_run(Repo, fn -> Delivest.Promo.Catalog.invalidate(branch.id) end)
    end
  end
end
