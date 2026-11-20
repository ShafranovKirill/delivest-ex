defmodule Delivest.Oms.Orders.CartGuardEpochLockTest do
  use ExUnit.Case, async: false

  import Delivest.Factory
  import Ecto.Query

  alias Delivest.Oms.{Cart, CartItem, Carts}
  alias Delivest.Oms.Orders.CartGuard
  alias Delivest.Repo
  alias Ecto.Adapters.SQL.Sandbox

  test "checkout holds the epoch row until commit and rejects a stale revision" do
    {branch, product, cart, revision, old_epoch} =
      Sandbox.unboxed_run(Repo, fn ->
        branch = insert(:branch)
        product = insert_branch_product(branch.id, price: 100)
        {:ok, cart} = Carts.create_cart(%{branch_id: branch.id, session_id: "epoch-lock-test"})

        {:ok, _, view} =
          Carts.add_item_for_session(cart.id, product.id, 1, nil, "epoch-lock-test")

        old_epoch = Repo.query!("SELECT epoch FROM storefront_epoch").rows |> hd() |> hd()
        {branch, product, cart, view.revision, old_epoch}
      end)

    owner = self()

    guard =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Repo.transaction(fn ->
            result = CartGuard.acquire(cart.id, branch.id, nil, cart_revision: revision)
            send(owner, {:guard_acquired, result})

            receive do
              :release -> :ok
            end
          end)
        end)
      end)

    try do
      assert_receive {:guard_acquired, {:ok, _}}, 10_000

      error =
        assert_raise Postgrex.Error, fn ->
          Sandbox.unboxed_run(Repo, fn ->
            Repo.transaction(fn ->
              Repo.query!("SET LOCAL lock_timeout = '100ms'")
              Repo.query!("UPDATE storefront_epoch SET epoch = md5(random()::text)")
            end)
          end)
        end

      assert error.postgres.code == :lock_not_available

      send(guard.pid, :release)
      assert {:ok, :ok} = Task.await(guard, 10_000)

      Sandbox.unboxed_run(Repo, fn ->
        Repo.query!("UPDATE storefront_epoch SET epoch = md5(random()::text)")

        assert {:ok, {:error, :cart_changed}} =
                 Repo.transaction(fn ->
                   CartGuard.acquire(cart.id, branch.id, nil, cart_revision: revision)
                 end)
      end)
    after
      send(guard.pid, :release)
      Task.shutdown(guard, 10_000)

      Sandbox.unboxed_run(Repo, fn ->
        Repo.query!("UPDATE storefront_epoch SET epoch = $1", [old_epoch])
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
