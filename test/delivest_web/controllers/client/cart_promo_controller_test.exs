defmodule DelivestWeb.Client.CartPromoControllerTest do
  use DelivestWeb.ConnCase, async: true

  import Delivest.Factory

  setup %{conn: conn} do
    branch = insert(:branch, is_active: true)
    pizza = insert_branch_product(branch.id, slug: "pizza", name: "Pizza", price: 500)
    insert_branch_product(branch.id, slug: "cola", name: "Cola", price: 90)

    conn = put_req_header(conn, "x-forwarded-for", "promo-#{System.unique_integer([:positive])}")
    conn = get(conn, ~p"/client/cart?branch_id=#{branch.id}")
    cart_id = json_response(conn, 200)["data"]["id"]
    conn = recycle_with_headers(conn)
    conn = post(conn, ~p"/client/cart/#{cart_id}/items/#{pizza.id}")
    assert json_response(conn, 200)

    %{conn: recycle_with_headers(conn), branch: branch, cart_id: cart_id, pizza: pizza}
  end

  defp recycle_with_headers(conn) do
    forwarded = get_req_header(conn, "x-forwarded-for")
    conn |> recycle() |> put_req_header("x-forwarded-for", Enum.join(forwarded, ","))
  end

  test "applies a code and marks gift lines", %{conn: conn, branch: branch, cart_id: cart_id} do
    promo =
      insert_promotion(branch.id,
        kind: :public_code,
        name: "Cola gift",
        rules: ~s(then gift "cola")
      )

    insert_code(promo, code: "COLA")

    data =
      conn |> post(~p"/client/cart/#{cart_id}/promo_code", %{code: "cola"}) |> json_response(200)

    assert %{"promo_code" => %{"code" => "COLA", "status" => "applied"}, "total_amount" => 500} =
             data["data"]

    assert [%{"gift" => false}, %{"gift" => true, "name" => "Cola", "total_price" => 0}] =
             data["data"]["items"]

    assert [%{"name" => "Cola gift", "gifts" => [%{"name" => "Cola"}]}] =
             data["data"]["promotions"]
  end

  test "returns a typed error for an unknown code", %{conn: conn, cart_id: cart_id} do
    assert %{"error" => "promo_not_found"} =
             conn
             |> post(~p"/client/cart/#{cart_id}/promo_code", %{code: "nope"})
             |> json_response(422)
  end

  test "asks guests to sign in for personal codes", %{
    conn: conn,
    branch: branch,
    cart_id: cart_id
  } do
    promo = insert_promotion(branch.id, kind: :personal_code)
    insert_code(promo, code: "PERSONAL", client_id: insert(:client).id)

    assert %{"error" => "promo_requires_client"} =
             conn
             |> post(~p"/client/cart/#{cart_id}/promo_code", %{code: "personal"})
             |> json_response(422)
  end

  test "recalculates after the fulfillment type changes", %{
    conn: conn,
    branch: branch,
    cart_id: cart_id
  } do
    insert_promotion(branch.id, rules: "when fulfillment in (pickup) then discount 10%")

    data =
      conn
      |> put(~p"/client/cart/#{cart_id}/context", %{fulfillment_type: "pickup"})
      |> json_response(200)

    assert %{"total_amount" => 450, "discount_amount" => 50, "fulfillment_type" => "pickup"} =
             data["data"]

    assert %{"error" => "validation_failed"} =
             conn
             |> recycle_with_headers()
             |> put(~p"/client/cart/#{cart_id}/context", %{fulfillment_type: "teleport"})
             |> json_response(422)
  end

  test "removes the code", %{conn: conn, branch: branch, cart_id: cart_id} do
    promo = insert_promotion(branch.id, kind: :public_code, rules: "then discount 100 rub")
    insert_code(promo, code: "HUNDRED")

    conn = post(conn, ~p"/client/cart/#{cart_id}/promo_code", %{code: "hundred"})
    assert json_response(conn, 200)["data"]["total_amount"] == 400

    data =
      conn
      |> recycle_with_headers()
      |> delete(~p"/client/cart/#{cart_id}/promo_code")
      |> json_response(200)

    assert %{"promo_code" => nil, "total_amount" => 500} = data["data"]
  end

  test "creates an order with the promotion summary", %{
    conn: conn,
    branch: branch,
    cart_id: cart_id
  } do
    promo =
      insert_promotion(branch.id,
        kind: :public_code,
        name: "Minus",
        rules: "then discount 100 rub"
      )

    insert_code(promo, code: "MINUS")
    conn = post(conn, ~p"/client/cart/#{cart_id}/promo_code", %{code: "minus"})
    assert json_response(conn, 200)

    params = %{
      "cart_id" => cart_id,
      "branch_id" => branch.id,
      "fulfillment_type" => "pickup",
      "payment_method" => "cash",
      "expected_total" => 400
    }

    data =
      conn |> recycle_with_headers() |> post(~p"/client/orders", params) |> json_response(200)

    assert %{
             "total_amount" => 400,
             "subtotal_amount" => 500,
             "discount_amount" => 100,
             "promotions" => [%{"name" => "Minus", "code" => "MINUS", "discount" => 100}]
           } = data["data"]
  end

  test "shows sale prices in the menu", %{conn: conn, branch: branch} do
    category = insert(:category)

    {:ok, _} =
      Delivest.Relations.create_relation(
        Delivest.Repo,
        "Branch",
        branch.id,
        "Category",
        category.id
      )

    burger =
      insert_branch_product(branch.id, slug: "burger", price: 500, category_id: category.id)

    insert_promotion(branch.id, rules: ~s(then price "burger" 399))

    data = conn |> get(~p"/client/branches/#{branch.id}/menu") |> json_response(200)
    products = Enum.flat_map(data["data"], & &1["products"])

    assert [%{"price" => 399, "old_price" => 500}] =
             Enum.filter(products, &(&1["id"] == burger.id))
  end
end
