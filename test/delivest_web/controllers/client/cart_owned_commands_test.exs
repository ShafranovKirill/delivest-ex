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
  end
end
