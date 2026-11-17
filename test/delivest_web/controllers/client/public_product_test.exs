defmodule DelivestWeb.Client.PublicProductTest do
  use DelivestWeb.ConnCase, async: false

  import Delivest.Factory
  alias Delivest.{Net, Repo, Relations}
  alias Delivest.Net.PublicOffers

  setup do
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    branch = insert(:branch, is_active: true)
    category = insert(:category)
    {:ok, _} = Relations.create_relation(Repo, "Branch", branch.id, "Category", category.id)

    product =
      insert_branch_product(branch.id,
        category_id: category.id,
        slug: "direct-product",
        description: "<script>private()</script>",
        stars_reward: 5
      )

    %{staff: staff, branch: branch, category: category, product: product}
  end

  test "point reads by UUID and slug match the menu projection including promo/rewards/stops",
       ctx do
    insert_promotion(ctx.branch.id, rules: ~s(then price "direct-product" 90))
    {:ok, _} = Net.Stops.stop(ctx.staff, ctx.branch.id, ctx.product, :until_resumed)
    menu = get(ctx.conn, ~p"/client/branches/#{ctx.branch.id}/menu") |> json_response(200)
    [category] = menu["data"]
    [expected] = category["products"]
    assert expected["price"] == 9_000
    assert expected["old_price"] == 10_000
    assert expected["stars_reward"] == 5
    assert expected["stopped"]

    for key <- [ctx.product.id, ctx.product.slug] do
      conn = get(build_conn(), "/client/branches/#{ctx.branch.id}/products/#{key}")
      assert json_response(conn, 200)["data"] == expected
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end
  end

  test "foreign branch, inactive category, deleted and invalid products are not exposed", ctx do
    other = insert(:branch, is_active: true)

    for key <- [ctx.product.id, ctx.product.slug, "missing"] do
      assert get(build_conn(), "/client/branches/#{other.id}/products/#{key}") |> response(404)
    end

    Repo.update!(Ecto.Changeset.change(ctx.category, is_active: false))
    assert {:error, :not_found} = PublicOffers.product(ctx.branch.id, ctx.product.id)
    Repo.update!(Ecto.Changeset.change(ctx.category, is_active: true))
    Repo.update!(Ecto.Changeset.change(ctx.product, deleted_at: DateTime.utc_now(:second)))
    assert {:error, :not_found} = PublicOffers.product(ctx.branch.id, ctx.product.id)
    assert {:error, :not_found} = PublicOffers.product("not-uuid", ctx.product.id)
  end

  test "point loading remains bounded as unrelated catalog grows", ctx do
    insert_promotion(ctx.branch.id, rules: ~s(then price "direct-product" 90))
    handler = "public-offer-bounded-#{System.unique_integer([:positive])}"
    pid = self()

    :telemetry.attach(
      handler,
      [:delivest, :repo, :query],
      fn _, _, metadata, _ ->
        if self() == pid, do: send(pid, {:offer_query, metadata.result})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    assert {:ok, _} = PublicOffers.product(ctx.branch.id, ctx.product.id)
    before = query_rows([])
    for _ <- 1..220, do: insert_branch_product(ctx.branch.id, category_id: ctx.category.id)
    query_rows([])
    assert {:ok, _} = PublicOffers.product(ctx.branch.id, ctx.product.id)
    after_growth = query_rows([])
    assert Enum.sum(after_growth) <= Enum.sum(before)
    assert length(after_growth) <= length(before)
    assert Enum.max(after_growth) <= 1
  end

  test "SEO canonical UUID, visible escaped content and absent landing status", ctx do
    path = "/#{ctx.branch.slug}/product/#{ctx.product.slug}"

    head =
      build_conn()
      |> put_req_header("x-original-uri", path <> "?yclid=123")
      |> get("/seo/head")
      |> html_response(200)

    assert head =~ "#{ctx.branch.slug}/product/#{ctx.product.id}"
    refute head =~ "yclid"

    content =
      build_conn()
      |> put_req_header("x-original-uri", path)
      |> get("/seo/content")
      |> html_response(200)

    assert content =~ "<h1>#{ctx.product.name}</h1>"
    assert content =~ "&lt;script&gt;private()&lt;/script&gt;"
    refute content =~ "<script>"

    assert build_conn()
           |> put_req_header("x-original-uri", path)
           |> get("/seo/landing-status")
           |> response(204)

    assert build_conn()
           |> put_req_header("x-original-uri", "/#{ctx.branch.slug}/product/missing")
           |> get("/seo/landing-status")
           |> response(403)

    assert build_conn()
           |> put_req_header("x-original-uri", "/#{ctx.branch.slug}/category/#{ctx.category.id}")
           |> get("/seo/content")
           |> html_response(200) =~ ctx.category.name
  end

  test "feed is unavailable while integration is disabled and XML uses immutable offer identity",
       ctx do
    assert get(ctx.conn, "/seo/branches/#{ctx.branch.slug}/catalog.xml") |> response(404)
    {:ok, offer} = PublicOffers.product(ctx.branch.id, ctx.product.id)

    xml =
      DelivestWeb.Seo.CatalogController.offer_xml(ctx.branch, ctx.category.id, offer)
      |> IO.iodata_to_binary()

    assert xml =~ "id=\"#{ctx.product.id}\""
    assert xml =~ "<price>100.00</price>"
    assert xml =~ "&lt;script&gt;"
    assert xml =~ "available=\"true\""
    assert xml =~ "/#{ctx.branch.slug}/product/#{ctx.product.id}"
  end

  test "sitemap index discovers bounded product pages and category URLs", ctx do
    index = get(ctx.conn, "/seo/sitemap.xml") |> response(200)
    assert index =~ "<sitemapindex"
    assert index =~ "/sitemaps/#{ctx.branch.slug}/products/0.xml"
    body = get(build_conn(), "/seo/sitemaps/#{ctx.branch.slug}/products/0.xml") |> response(200)
    assert body =~ "/#{ctx.branch.slug}/product/#{ctx.product.id}"
    assert get(build_conn(), "/seo/sitemaps/#{ctx.branch.slug}/products/1.xml") |> response(404)

    categories =
      get(build_conn(), "/seo/sitemaps/#{ctx.branch.slug}/categories.xml") |> response(200)

    assert categories =~ "/#{ctx.branch.slug}/category/#{ctx.category.id}"
  end

  test "enabled feed shares menu prices and excludes virtual popular duplicates", ctx do
    alias Delivest.Integrations.YandexAds
    alias Delivest.Features
    assert {:ok, _} = Features.configure("yandex_feed", :franchise, true, actor: "host")

    assert {:ok, _} =
             Features.configure("yandex_feed", {:branch, ctx.branch.id}, true, actor: "host")

    assert {:ok, _} =
             YandexAds.update_settings(ctx.staff, %{
               enabled: true,
               feed_enabled: true,
               branch_ids: [ctx.branch.id]
             })

    insert_promotion(ctx.branch.id, rules: ~s(then price "direct-product" 90))

    assert {:ok, _} =
             Delivest.Popular.update_settings(ctx.staff, ctx.branch.id, %{
               mode: "manual",
               show_in_menu: true
             })

    assert {:ok, _} = Delivest.Popular.add_product(ctx.staff, ctx.branch.id, ctx.product.id)
    conn = get(ctx.conn, "/seo/branches/#{ctx.branch.slug}/catalog.xml")
    xml = response(conn, 200)
    assert xml =~ "<price>90.00</price>"
    assert xml =~ "<oldprice>100.00</oldprice>"
    assert length(Regex.scan(~r/<offer id=/, xml)) == 1
    refute xml =~ "00000000-0000-4000-8000-000000000001"
    assert xml =~ "</yml_catalog>"

    assert {:ok, _} =
             Features.configure("yandex_feed", {:branch, ctx.branch.id}, false, actor: "host")

    assert get(build_conn(), "/seo/branches/#{ctx.branch.slug}/catalog.xml") |> response(404)
  end

  test "required stopped modifier is exposed consistently and makes feed unavailable", ctx do
    alias Delivest.Net.{ModifierGroup, Modifier, ModifierStop, ProductModifierGroup}
    group = Repo.insert!(%ModifierGroup{name: "Size", min: 1, max: 1, is_active: true})

    modifier =
      Repo.insert!(%Modifier{group_id: group.id, name: "Large", price: 500, is_active: true})

    Repo.insert!(%ProductModifierGroup{group_id: group.id, product_id: ctx.product.id})
    Repo.insert!(%ModifierStop{branch_id: ctx.branch.id, modifier_id: modifier.id})
    {:ok, offer} = PublicOffers.product(ctx.branch.id, ctx.product.id)
    assert [%{min: 1, modifiers: [%{stopped: true}]}] = offer.modifier_groups
    refute PublicOffers.purchasable?(offer)

    xml =
      DelivestWeb.Seo.CatalogController.offer_xml(ctx.branch, ctx.category.id, offer)
      |> IO.iodata_to_binary()

    assert xml =~ "available=\"false\""
    menu = get(ctx.conn, "/client/branches/#{ctx.branch.id}/menu") |> json_response(200)

    assert hd(hd(menu["data"])["products"])["modifier_groups"] ==
             Jason.decode!(Jason.encode!(offer.modifier_groups))
  end

  defp query_rows(rows) do
    receive do
      {:offer_query, {:ok, %{num_rows: count}}} -> query_rows([count | rows])
      {:offer_query, _} -> query_rows(rows)
    after
      0 -> rows
    end
  end
end
