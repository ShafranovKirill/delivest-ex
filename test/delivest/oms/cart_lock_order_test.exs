defmodule Delivest.Oms.CartLockOrderTest do
  use ExUnit.Case, async: false

  import Delivest.Factory
  import Ecto.Query

  alias Delivest.Oms.{Cart, CartItem, Carts}
  alias Delivest.Repo
  alias Ecto.Adapters.SQL.Sandbox

  test "clear and add complete on separate database connections with cart-first locks" do
    {branch, product, cart} =
      Sandbox.unboxed_run(Repo, fn ->
        branch = insert(:branch)
        product = insert_branch_product(branch.id, price: 100)
        {:ok, cart} = Carts.create_cart(%{branch_id: branch.id, session_id: "lock-order-test"})
        {:ok, _, _} = Carts.add_item(cart.id, product.id)
        {branch, product, cart}
      end)

    try do
      for _ <- 1..8 do
        clear =
          Task.async(fn ->
            receive do
              :go ->
                Sandbox.unboxed_run(Repo, fn ->
                  Carts.clear_cart_for_session(cart.id, "lock-order-test")
                end)
            end
          end)

        add =
          Task.async(fn ->
            receive do
              :go ->
                Sandbox.unboxed_run(Repo, fn ->
                  Carts.add_item_for_session(cart.id, product.id, 1, nil, "lock-order-test")
                end)
            end
          end)

        send(clear.pid, :go)
        send(add.pid, :go)

        assert Enum.all?(
                 Task.await_many([clear, add], 10_000),
                 &(match?({:ok, _}, &1) or match?({:ok, _, _}, &1))
               )
      end

      Sandbox.unboxed_run(Repo, fn ->
        assert Repo.aggregate(from(ci in CartItem, where: ci.cart_id == ^cart.id), :count) in [
                 0,
                 1
               ]

        assert Carts.get_cart_by_id(cart.id, force: true)
      end)
    after
      Sandbox.unboxed_run(Repo, fn ->
        Repo.delete_all(from ci in CartItem, where: ci.cart_id == ^cart.id)
        Repo.delete!(Repo.get!(Cart, cart.id))

        Repo.delete_all(
          from r in Delivest.Relations.EntityRelation, where: r.from_id == ^branch.id
        )

        Repo.delete!(product)
        Repo.delete!(branch)
      end)

      Cachex.del(:cart_cache, cart.id)
    end
  end
end
