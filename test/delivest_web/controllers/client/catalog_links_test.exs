defmodule DelivestWeb.Client.CatalogLinksTest do
  use DelivestWeb.ConnCase, async: true

  import Delivest.Factory

  alias Delivest.{Net, Popular}

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

  test "warm menu GET does not read popular settings or analytics", ctx do
    {:ok, _} = Popular.update_settings(ctx.staff, ctx.branch.id, %{"mode" => "auto"})
    path = ~p"/client/branches/#{ctx.branch.id}/menu"
    handler = "popular-menu-query-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler,
        [:delivest, :repo, :query],
        fn _, _, metadata, _ ->
          if self() == test_pid, do: send(test_pid, {:menu_sql, metadata.query})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    assert ctx.conn |> get(path) |> json_response(200)
    cold_queries = collect_menu_sql([])
    refute Enum.any?(cold_queries, &String.contains?(&1, "order_items"))

    assert build_conn() |> get(path) |> json_response(200)

    queries = collect_menu_sql([])
    refute Enum.any?(queries, &String.contains?(&1, "popular_settings"))
    refute Enum.any?(queries, &String.contains?(&1, "popular_products"))
    refute Enum.any?(queries, &String.contains?(&1, "order_items"))
  end

  defp collect_menu_sql(acc) do
    receive do
      {:menu_sql, query} -> collect_menu_sql([query | acc])
    after
      0 -> acc
    end
  end

  test "popular display options are independent and preserve product data", ctx do
    assert %{"data" => [category]} =
             ctx.conn |> get(~p"/client/branches/#{ctx.branch.id}/menu") |> json_response(200)

    assert [%{"popular" => false}] = category["products"]

    previous_version = Delivest.Repo.get!(Delivest.Identity.Branch, ctx.branch.id).catalog_version

    {:ok, _} = Popular.update_settings(ctx.staff, ctx.branch.id, %{"mode" => "manual"})
    {:ok, _} = Popular.add_product(ctx.staff, ctx.branch.id, ctx.product.id)

    assert Delivest.Repo.get!(Delivest.Identity.Branch, ctx.branch.id).catalog_version >
             previous_version

    assert %{"data" => [category]} =
             build_conn() |> get(~p"/client/branches/#{ctx.branch.id}/menu") |> json_response(200)

    assert [%{"popular" => true}] = category["products"]

    {:ok, _} =
      Popular.update_settings(ctx.staff, ctx.branch.id, %{
        "show_in_menu" => true,
        "show_in_cart" => false
      })

    assert %{"data" => [popular, category]} =
             build_conn() |> get(~p"/client/branches/#{ctx.branch.id}/menu") |> json_response(200)

    assert popular["id"] == "00000000-0000-4000-8000-000000000001"
    assert popular["name"] == "Popular"
    assert popular["products"] == category["products"]
    assert [%{"popular" => false}] = popular["products"]

    {:ok, _} = Popular.update_settings(ctx.staff, ctx.branch.id, %{"show_in_cart" => true})

    assert %{"data" => [popular, _category]} =
             build_conn() |> get(~p"/client/branches/#{ctx.branch.id}/menu") |> json_response(200)

    assert [%{"popular" => true}] = popular["products"]

    {:ok, _} =
      Popular.update_settings(ctx.staff, ctx.branch.id, %{
        "show_in_menu" => false,
        "show_in_cart" => false
      })

    assert %{"data" => [category]} =
             build_conn() |> get(~p"/client/branches/#{ctx.branch.id}/menu") |> json_response(200)

    assert [%{"popular" => false}] = category["products"]

    {:ok, _} = Popular.update_settings(ctx.staff, ctx.branch.id, %{"mode" => "off"})

    assert %{"data" => [category]} =
             build_conn() |> get(~p"/client/branches/#{ctx.branch.id}/menu") |> json_response(200)

    assert [%{"popular" => false}] = category["products"]
  end

  test "empty popular selection creates no category", ctx do
    {:ok, _} =
      Popular.update_settings(ctx.staff, ctx.branch.id, %{
        "mode" => "manual",
        "show_in_menu" => true
      })

    assert %{"data" => [_category]} =
             ctx.conn |> get(~p"/client/branches/#{ctx.branch.id}/menu") |> json_response(200)
  end

  test "popular category uses the request locale and promotion prices", ctx do
    {:ok, _} = Net.update_product(ctx.staff, ctx.product, %{"price" => 30_000})
    insert_promotion(ctx.branch.id, rules: ~s(then price "hinkali" 199))

    {:ok, _} =
      Popular.update_settings(ctx.staff, ctx.branch.id, %{
        "mode" => "manual",
        "show_in_menu" => true
      })

    {:ok, _} = Popular.add_product(ctx.staff, ctx.branch.id, ctx.product.id)

    conn = put_req_header(build_conn(), "accept-language", "ru-RU,ru;q=0.9")

    assert %{"data" => [popular, category]} =
             conn |> get(~p"/client/branches/#{ctx.branch.id}/menu") |> json_response(200)

    assert popular["name"] == "Популярное"
    assert [%{"price" => 19_900, "old_price" => 30_000}] = popular["products"]
    assert popular["products"] == category["products"]
  end

  test "menu exposes the measure unit", %{
    conn: conn,
    staff: staff,
    branch: branch,
    product: product
  } do
    body = conn |> get(~p"/client/branches/#{branch.id}/menu") |> json_response(200)
    assert [%{"products" => [%{"measure_unit" => "g"}]}] = body["data"]

    {:ok, _} = Net.update_product(staff, product, %{"measure_unit" => "ml", "weight" => 500})

    body = build_conn() |> get(~p"/client/branches/#{branch.id}/menu") |> json_response(200)
    assert [%{"products" => [%{"measure_unit" => "ml", "weight" => 500}]}] = body["data"]
  end

  test "menu exposes product tags with icons and the cart suggestion flag", %{
    conn: conn,
    staff: staff,
    branch: branch,
    product: product
  } do
    tag = Delivest.Repo.get_by!(Delivest.Net.ProductTag, name: "Новинка")

    {:ok, _} =
      Net.update_product(staff, product, %{
        "tags" => [tag.id, Ecto.UUID.generate()],
        "suggested" => true
      })

    body = conn |> get(~p"/client/branches/#{branch.id}/menu") |> json_response(200)

    assert [%{"products" => [%{"tags" => [json_tag], "suggested" => true}]}] = body["data"]
    assert json_tag["id"] == tag.id
    assert json_tag["name"] == "Новинка"
    assert json_tag["icon_url"] =~ "/images/tag-icons/sparkles.svg"
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
