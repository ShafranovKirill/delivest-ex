defmodule Delivest.Oms.Orders.IdempotencyConcurrencyTest do
  use ExUnit.Case, async: false

  import Delivest.Factory
  import Ecto.Query

  alias Delivest.Oms.{Cart, Carts, Order, Orders}
  alias Delivest.Repo
  alias Ecto.Adapters.SQL.Sandbox

  test "two PostgreSQL connections create one order for the same owner and key" do
    {branch, product, cart, session_id} =
      Sandbox.unboxed_run(Repo, fn ->
        branch = insert(:branch, is_active: true)
        product = insert_branch_product(branch.id, price: 300)
        session_id = Ecto.UUID.generate()
        {:ok, cart} = Carts.create_cart(%{branch_id: branch.id, session_id: session_id})
        {:ok, _, _} = Carts.add_item(cart.id, product.id)
        {branch, product, cart, session_id}
      end)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        order_ids = Repo.all(from o in Order, where: o.cart_id == ^cart.id, select: o.id)

        for id <- order_ids do
          Repo.query!(
            "DELETE FROM oban_jobs WHERE args->>'event_id' IN (SELECT id::text FROM domain_events WHERE aggregate_id = $1)",
            [Ecto.UUID.dump!(id)]
          )

          Repo.query!("DELETE FROM domain_events WHERE aggregate_id = $1", [Ecto.UUID.dump!(id)])
          Repo.query!("DELETE FROM audit_events WHERE subject_id = $1", [id])
        end

        Repo.delete_all(from o in Order, where: o.cart_id == ^cart.id)

        Repo.query!("DELETE FROM order_counters WHERE branch_id = $1", [
          Ecto.UUID.dump!(branch.id)
        ])

        Repo.delete!(Repo.get!(Cart, cart.id))

        Repo.delete_all(
          from r in Delivest.Relations.EntityRelation,
            where: r.from_id == ^branch.id or r.to_id == ^product.id
        )

        Repo.delete!(product)
        Repo.delete!(branch)
      end)

      Cachex.del(:cart_cache, cart.id)
    end)

    key = Ecto.UUID.generate()

    attrs = %{
      "cart_id" => cart.id,
      "branch_id" => branch.id,
      "session_id" => session_id,
      "fulfillment_type" => "pickup",
      "payment_method" => "cash"
    }

    opts = [
      update_client: false,
      guest_session_access: true,
      public_session_id: session_id,
      public_guest: true,
      idempotency: %{owner: "guest:#{session_id}", key: key, fingerprint: "same"},
      preflight: fn -> :ok end
    ]

    parent = self()

    locker =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Repo.transaction(fn ->
            Repo.query!("SELECT id FROM cart_items WHERE cart_id = $1 FOR UPDATE", [
              Ecto.UUID.dump!(cart.id)
            ])

            send(parent, :cart_item_locked)
            receive do: (:unlock_cart_item -> :ok)
          end)
        end)
      end)

    assert_receive :cart_item_locked

    assert {:error, :cart, :cart_changed} =
             Sandbox.unboxed_run(Repo, fn -> Orders.create_order(attrs, opts) end)

    send(locker.pid, :unlock_cart_item)
    assert {:ok, :ok} = Task.await(locker)

    tasks =
      for _ <- 1..2 do
        Task.async(fn ->
          receive do
            :create -> Sandbox.unboxed_run(Repo, fn -> Orders.create_order(attrs, opts) end)
          end
        end)
      end

    Enum.each(tasks, &send(&1.pid, :create))
    results = Task.await_many(tasks, 15_000)
    assert Enum.count(results, &match?({:ok, %Order{}}, &1)) == 1
    assert Enum.count(results, &match?({:ok, %Order{}, :replay}, &1)) == 1

    Sandbox.unboxed_run(Repo, fn ->
      assert Repo.aggregate(from(o in Order, where: o.cart_id == ^cart.id), :count) == 1
    end)
  end
end
