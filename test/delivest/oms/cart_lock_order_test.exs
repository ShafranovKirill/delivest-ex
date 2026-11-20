defmodule Delivest.Oms.CartLockOrderTest do
  use ExUnit.Case, async: false

  import Delivest.Factory
  import Ecto.Query

  alias Delivest.Oms.{Cart, CartItem, Carts, Order, OrderItem}
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

  test "clear races with replace, remove, and context on separate connections" do
    {branch, product, cart} =
      Sandbox.unboxed_run(Repo, fn ->
        branch = insert(:branch)
        product = insert_branch_product(branch.id, price: 100)
        {:ok, cart} = Carts.create_cart(%{branch_id: branch.id, session_id: "command-lock-test"})
        {branch, product, cart}
      end)

    commands = [
      fn -> Carts.replace_item_for_session(cart.id, product.id, [], "command-lock-test") end,
      fn -> Carts.remove_item_for_session(cart.id, product.id, [], "command-lock-test") end,
      fn ->
        Carts.update_context_for_session(
          cart.id,
          %{fulfillment_type: "pickup"},
          "command-lock-test"
        )
      end
    ]

    try do
      for command <- commands, _ <- 1..3 do
        Sandbox.unboxed_run(Repo, fn ->
          assert {:ok, _, _} =
                   Carts.add_item_for_session(cart.id, product.id, 1, nil, "command-lock-test")
        end)

        clear =
          Task.async(fn ->
            Sandbox.unboxed_run(Repo, fn ->
              Carts.clear_cart_for_session(cart.id, "command-lock-test")
            end)
          end)

        mutate = Task.async(fn -> Sandbox.unboxed_run(Repo, command) end)

        assert {:ok, _} = Task.await(clear, 10_000)
        result = Task.await(mutate, 10_000)

        assert result in [
                 {:error, :item_not_found},
                 {:error, :not_found},
                 {:error, :order_not_found}
               ] or match?({:ok, _}, result) or match?({:ok, _, _}, result)
      end
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

  test "waiting remove, context, and repeat reject a detached cart" do
    {branch, product, client, historical, order} =
      Sandbox.unboxed_run(Repo, fn ->
        branch = insert(:branch)
        product = insert_branch_product(branch.id, price: 100)
        client = insert(:client)
        {:ok, historical} = Carts.create_cart(%{branch_id: branch.id, session_id: "historic"})

        order =
          Repo.insert!(%Order{
            number: "RACE-#{System.unique_integer([:positive])}",
            daily_number: 1,
            business_date: Date.utc_today(),
            branch_id: branch.id,
            cart_id: historical.id,
            client_id: client.id
          })

        Repo.insert!(%OrderItem{
          order_id: order.id,
          product_id: product.id,
          title: "Product",
          price: 100,
          quantity: 1
        })

        {branch, product, client, historical, order}
      end)

    try do
      for command <- [:remove, :context, :repeat] do
        cart =
          Sandbox.unboxed_run(Repo, fn ->
            {:ok, cart} =
              Carts.create_cart(%{branch_id: branch.id, session_id: "detach-race"})

            {:ok, _, _} =
              Carts.add_item_for_session(cart.id, product.id, 1, nil, "detach-race")

            cart
          end)

        owner = self()
        cart_id = cart.id

        detach =
          Task.async(fn ->
            Sandbox.unboxed_run(Repo, fn ->
              Repo.transaction(fn ->
                locked = Repo.one!(from c in Cart, where: c.id == ^cart.id, lock: "FOR UPDATE")
                send(owner, {:cart_locked, cart.id})

                receive do
                  :detach -> :ok
                end

                locked |> Ecto.Changeset.change(session_id: nil) |> Repo.update!()
              end)
            end)
          end)

        mutation =
          Task.async(fn ->
            Sandbox.unboxed_run(Repo, fn ->
              receive do
                :run -> :ok
              end

              [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
              send(owner, {:mutation_backend, backend_pid})

              case command do
                :remove ->
                  Carts.remove_item_for_session(cart.id, product.id, [], "detach-race")

                :context ->
                  Carts.update_context_for_session(
                    cart.id,
                    %{fulfillment_type: "pickup"},
                    "detach-race"
                  )

                :repeat ->
                  Carts.repeat_order_for_session(cart.id, "detach-race", client.id, order.id)
              end
            end)
          end)

        try do
          assert_receive {:cart_locked, ^cart_id}, 10_000
          send(mutation.pid, :run)
          assert_receive {:mutation_backend, backend_pid}, 10_000

          assert_backend_waiting_for_lock(
            backend_pid,
            System.monotonic_time(:millisecond) + 10_000
          )

          send(detach.pid, :detach)
          assert {:ok, _} = Task.await(detach, 10_000)
          assert {:error, :cart_not_found} = Task.await(mutation, 10_000)

          Sandbox.unboxed_run(Repo, fn ->
            assert Repo.get!(Cart, cart.id).session_id == nil
            assert Repo.get!(Cart, cart.id).fulfillment_type == nil

            assert Repo.one!(
                     from ci in CartItem, where: ci.cart_id == ^cart.id, select: ci.quantity
                   ) == 1
          end)
        after
          send(detach.pid, :detach)
          send(mutation.pid, :run)
          Task.shutdown(detach, 10_000)
          Task.shutdown(mutation, 10_000)

          Sandbox.unboxed_run(Repo, fn ->
            Repo.delete_all(from ci in CartItem, where: ci.cart_id == ^cart.id)
            Repo.delete!(Repo.get!(Cart, cart.id))
          end)

          Cachex.del(:cart_cache, cart.id)
        end
      end
    after
      Sandbox.unboxed_run(Repo, fn ->
        Repo.delete_all(from oi in OrderItem, where: oi.order_id == ^order.id)
        Repo.delete!(Repo.get!(Order, order.id))
        Repo.delete!(Repo.get!(Cart, historical.id))

        Repo.delete_all(
          from r in Delivest.Relations.EntityRelation, where: r.from_id == ^branch.id
        )

        Repo.delete!(product)
        Repo.delete!(client)
        Repo.delete!(branch)
      end)

      Cachex.del(:cart_cache, historical.id)
    end
  end

  defp assert_backend_waiting_for_lock(backend_pid, deadline) do
    waiting? =
      Sandbox.unboxed_run(Repo, fn ->
        Repo.query!("SELECT wait_event_type FROM pg_stat_activity WHERE pid = $1", [backend_pid]).rows ==
          [["Lock"]]
      end)

    cond do
      waiting? ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("mutation backend did not wait for the cart row lock")

      true ->
        receive do
        after
          10 -> assert_backend_waiting_for_lock(backend_pid, deadline)
        end
    end
  end
end
