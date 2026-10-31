defmodule DelivestWeb.Client.CartModifiersControllerTest do
  use DelivestWeb.ConnCase, async: true

  import Delivest.Factory
  import Delivest.YandexEdaFixtures

  alias Delivest.Net.{Modifier, ModifierGroup, ProductModifierGroup}
  alias Delivest.Repo

  setup %{conn: conn} do
    branch = insert(:branch, is_active: true)
    pizza = menu_product(branch, menu_category(branch), name: "Pizza", price: 50_000)
    size = Repo.insert!(%ModifierGroup{name: "Размер", min: 1, max: 1})
    Repo.insert!(%Modifier{group_id: size.id, name: "25 см", price: 0, is_default: true})
    large = Repo.insert!(%Modifier{group_id: size.id, name: "35 см", price: 20_000})
    Repo.insert!(%ProductModifierGroup{product_id: pizza.id, group_id: size.id})

    conn = put_req_header(conn, "x-forwarded-for", "mods-#{System.unique_integer([:positive])}")
    conn = get(conn, ~p"/client/cart?branch_id=#{branch.id}")
    cart_id = json_response(conn, 200)["data"]["id"]

    %{
      conn: recycle_with_headers(conn),
      branch: branch,
      cart_id: cart_id,
      pizza: pizza,
      large: large
    }
  end

  defp recycle_with_headers(conn) do
    forwarded = get_req_header(conn, "x-forwarded-for")
    conn |> recycle() |> put_req_header("x-forwarded-for", Enum.join(forwarded, ","))
  end

  test "the menu shows the groups and the cart takes a choice", ctx do
    menu = ctx.conn |> get(~p"/client/branches/#{ctx.branch.id}/menu") |> json_response(200)

    product =
      menu["data"] |> Enum.flat_map(& &1["products"]) |> Enum.find(&(&1["id"] == ctx.pizza.id))

    assert [%{"name" => "Размер", "min" => 1, "modifiers" => [_, _]}] = product["modifier_groups"]

    data =
      ctx.conn
      |> recycle_with_headers()
      |> post(~p"/client/cart/#{ctx.cart_id}/items/#{ctx.pizza.id}", %{
        modifiers: [%{id: ctx.large.id}]
      })
      |> json_response(200)

    assert [%{"key" => key, "price" => 70_000, "modifiers" => [%{"name" => "35 см"}]}] =
             data["data"]["items"]

    data =
      ctx.conn
      |> recycle_with_headers()
      |> delete(~p"/client/cart/#{ctx.cart_id}/items/#{key}")
      |> json_response(200)

    assert data["data"]["items"] == []
  end
end
