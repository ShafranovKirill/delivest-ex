defmodule DelivestWeb.Client.CartOwnedCommandsTest do
  use DelivestWeb.ConnCase, async: false

  import Delivest.Factory

  alias Delivest.Oms.Carts

  setup do
    branch = insert(:branch, is_active: true)
    product = insert_branch_product(branch.id, price: 10_000)
    session_id = Ecto.UUID.generate()
    {:ok, cart} = Carts.create_cart(%{branch_id: branch.id, session_id: session_id})
    %{branch: branch, product: product, cart: cart, session_id: session_id}
  end

  test "foreign and malformed cart IDs stay opaque across cart mutations", ctx do
    for {cart_id, session_id} <- [
          {ctx.cart.id, Ecto.UUID.generate()},
          {"not-a-uuid", ctx.session_id}
        ] do
      conn = Plug.Test.put_req_cookie(build_conn(), "session_id", session_id)

      assert %{"error" => "cart_not_found"} =
               conn
               |> post("/client/cart/#{cart_id}/items/#{ctx.product.id}", %{})
               |> json_response(404)

      assert %{"error" => "cart_not_found"} =
               conn
               |> put("/client/cart/#{cart_id}/items/#{ctx.product.id}", %{modifiers: []})
               |> json_response(404)

      assert %{"error" => "cart_not_found"} =
               conn
               |> post("/client/cart/#{cart_id}/promo_code", %{code: "WRONG"})
               |> json_response(404)

      assert %{"error" => "cart_not_found"} =
               conn
               |> put("/client/cart/#{cart_id}/promotions/#{Ecto.UUID.generate()}/gifts", %{
                 product_ids: []
               })
               |> json_response(404)

      assert %{"error" => "cart_not_found"} =
               conn |> delete("/client/cart/#{cart_id}/clear") |> json_response(404)

      assert %{"error" => "cart_not_found"} =
               conn
               |> delete("/client/cart/#{cart_id}/items/#{ctx.product.id}")
               |> json_response(404)

      assert %{"error" => "cart_not_found"} =
               conn
               |> put("/client/cart/#{cart_id}/context", %{fulfillment_type: "pickup"})
               |> json_response(404)

      assert %{"error" => "cart_not_found"} =
               conn
               |> post("/client/cart/#{cart_id}/repeat/#{Ecto.UUID.generate()}")
               |> json_response(404)
    end
  end

  test "detached cart cannot be changed by its former session", ctx do
    assert {:ok, _} = Carts.detach_cart(ctx.cart.id)
    conn = Plug.Test.put_req_cookie(build_conn(), "session_id", ctx.session_id)

    assert %{"error" => "cart_not_found"} =
             conn
             |> post("/client/cart/#{ctx.cart.id}/items/#{ctx.product.id}", %{})
             |> json_response(404)

    assert %{"error" => "cart_not_found"} =
             conn
             |> post("/client/cart/#{ctx.cart.id}/promo_code", %{code: "WRONG"})
             |> json_response(404)

    assert %{"error" => "cart_not_found"} =
             conn
             |> delete("/client/cart/#{ctx.cart.id}/items/#{ctx.product.id}")
             |> json_response(404)

    assert %{"error" => "cart_not_found"} =
             conn
             |> put("/client/cart/#{ctx.cart.id}/context", %{fulfillment_type: "pickup"})
             |> json_response(404)

    assert %{"error" => "cart_not_found"} =
             conn
             |> post("/client/cart/#{ctx.cart.id}/repeat/#{Ecto.UUID.generate()}")
             |> json_response(404)
  end

  test "missing session cannot mutate a known cart", ctx do
    assert {:error, :cart_not_found} =
             Carts.remove_item_for_session(ctx.cart.id, ctx.product.id, [], nil)

    assert {:error, :cart_not_found} =
             Carts.update_context_for_session(ctx.cart.id, %{fulfillment_type: "pickup"}, nil)

    assert {:error, :cart_not_found} =
             Carts.repeat_order_for_session(ctx.cart.id, nil, nil, Ecto.UUID.generate())
  end

  test "owned remove decrements and deletes only the requested item", ctx do
    assert {:ok, _, _} =
             Carts.add_item_for_session(ctx.cart.id, ctx.product.id, 2, nil, ctx.session_id)

    conn = Plug.Test.put_req_cookie(build_conn(), "session_id", ctx.session_id)

    assert %{"items" => [%{"quantity" => 1}]} =
             conn
             |> delete("/client/cart/#{ctx.cart.id}/items/#{ctx.product.id}")
             |> json_response(200)
             |> Map.fetch!("data")

    assert %{"items" => []} =
             conn
             |> delete("/client/cart/#{ctx.cart.id}/items/#{ctx.product.id}?all=true")
             |> json_response(200)
             |> Map.fetch!("data")
  end

  test "invalid context leaves the owned cart unchanged", ctx do
    conn = Plug.Test.put_req_cookie(build_conn(), "session_id", ctx.session_id)

    assert %{"error" => "validation_failed"} =
             conn
             |> put("/client/cart/#{ctx.cart.id}/context", %{fulfillment_type: "teleport"})
             |> json_response(422)

    assert Carts.get_cart_by_id_for_session(ctx.cart.id, ctx.session_id).fulfillment_type == nil
  end

  test "malformed order ID returns order not found for an owned cart", ctx do
    conn = Plug.Test.put_req_cookie(build_conn(), "session_id", ctx.session_id)

    assert %{"error" => "order_not_found"} =
             conn
             |> post("/client/cart/#{ctx.cart.id}/repeat/not-an-order")
             |> json_response(404)

    client = insert(:client)

    assert {:error, :order_not_found} =
             Carts.repeat_order_for_session(
               ctx.cart.id,
               ctx.session_id,
               client.id,
               "not-an-order"
             )
  end

  test "outer transaction rollback cannot publish an added item", ctx do
    assert {:ok, original} = Cachex.get(:cart_cache, ctx.cart.id)

    assert {:error, :cancelled} =
             Delivest.Repo.transaction(fn ->
               assert {:ok, _, view} =
                        Carts.add_item_for_session(
                          ctx.cart.id,
                          ctx.product.id,
                          1,
                          nil,
                          ctx.session_id
                        )

               assert length(view.items) == 1
               Delivest.Repo.rollback(:cancelled)
             end)

    assert {:ok, ^original} = Cachex.get(:cart_cache, ctx.cart.id)
    assert Carts.get_cart_by_id_for_session(ctx.cart.id, ctx.session_id).items == []
  end
end
