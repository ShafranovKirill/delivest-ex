defmodule DelivestWeb.Client.CatalogLinksTest do
  use DelivestWeb.ConnCase, async: true

  import Delivest.Factory

  alias Delivest.Net

  setup do
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    branch = insert(:branch, is_active: true)
    category = insert(:category, name: "Горячее")

    {:ok, _} =
      Delivest.Relations.create_relation(
        Delivest.Repo,
        "Branch",
        branch.id,
        "Category",
        category.id
      )

    {:ok, product} =
      Net.create_product(staff, branch.id, %{
        "name" => "Хинкали",
        "price" => 300,
        "category_id" => category.id
      })

    media =
      Delivest.Repo.insert!(%Delivest.Media.File{
        bucket: "delivest",
        key: "stock/banner.jpg",
        original_name: "banner.jpg",
        mime_type: "image/jpeg",
        size: 100,
        context: :stock,
        owner_id: branch.id,
        is_private: false
      })

    %{staff: staff, branch: branch, product: product, media: media}
  end

  test "menu exposes product slugs", %{conn: conn, branch: branch} do
    body = conn |> get(~p"/client/branches/#{branch.id}/menu") |> json_response(200)
    assert [%{"products" => [%{"slug" => "hinkali"}]}] = body["data"]
  end

  test "menu exposes product labels", %{
    conn: conn,
    staff: staff,
    branch: branch,
    product: product
  } do
    {:ok, _} = Net.update_product(staff, product, %{"tags" => ["new", "vegetarian"]})

    body = conn |> get(~p"/client/branches/#{branch.id}/menu") |> json_response(200)
    assert [%{"products" => [%{"tags" => ["new", "vegetarian"]}]}] = body["data"]
  end

  test "a promotion links to its product while the product is available", ctx do
    {:ok, _stock} =
      Net.create_stock(ctx.staff, ctx.branch.id, %{
        "media_id" => ctx.media.id,
        "text" => "Хинкали -20%",
        "product_id" => ctx.product.id
      })

    body = ctx.conn |> get(~p"/client/#{ctx.branch.id}/stocks") |> json_response(200)
    assert [%{"product_slug" => "hinkali"}] = body["data"]

    {:ok, _} = Net.update_product(ctx.staff, ctx.product, %{"is_active" => false})

    body = build_conn() |> get(~p"/client/#{ctx.branch.id}/stocks") |> json_response(200)
    assert [%{"product_slug" => nil}] = body["data"]
  end

  test "an invalid branch id is a bad request", %{conn: conn} do
    assert %{"error" => "bad_request"} =
             conn |> get(~p"/client/branches/not-a-uuid/menu") |> json_response(400)
  end
end
