defmodule DelivestWeb.Seo.SeoControllerTest do
  use DelivestWeb.ConnCase, async: false

  import Delivest.Factory

  alias Delivest.Franchise

  setup do
    Cachex.clear(:franchise_cache)
    Delivest.S3Stub.record(self())
    %{admin: insert(:staff, role: insert(:role, permissions: ["admin"]))}
  end

  describe "head" do
    test "falls back to the Delivest images before the franchise uploads its own", %{conn: conn} do
      html =
        conn
        |> put_req_header("x-original-uri", "/center/promotions?utm_source=tg")
        |> get(~p"/seo/head")
        |> html_response(200)

      assert html =~ "<title>Delivest</title>"
      assert html =~ ~s(<link rel="canonical" href="http://localhost:3000/center/promotions">)

      assert html =~ ~s(<link rel="icon" href="http://localhost:4000/images/seo/favicon.ico")

      assert html =~
               ~s(<meta property="og:image" content="http://localhost:4000/images/seo/og-image.png">)

      assert html =~ ~s(<meta name="twitter:card" content="summary_large_image">)
      refute html =~ "description"
    end

    test "uses franchise settings and uploaded images", %{conn: conn, admin: admin} do
      {:ok, _} =
        Franchise.update_settings(admin, %{
          "name" => "Суши <Like>",
          "description" => "Доставка роллов",
          "primary_color" => "#123456",
          "dark_primary_color" => "#abcdef",
          "default_theme" => "dark"
        })

      {:ok, %{icon_key: icon}} = Franchise.update_icon(admin, Delivest.S3Stub.png(512, 512))

      {:ok, %{share_image_key: share}} =
        Franchise.update_share_image(admin, Delivest.S3Stub.png(1200, 630))

      html = conn |> get(~p"/seo/head") |> html_response(200)

      assert html =~ "<title>Суши &lt;Like&gt;</title>"
      assert html =~ ~s(<meta name="description" content="Доставка роллов">)
      assert html =~ ~s(<meta name="theme-color" content="#123456">)
      assert html =~ ~s(<meta name="delivest-brand-color-dark" content="#abcdef">)
      assert html =~ ~s(<meta name="delivest-default-theme" content="dark">)
      assert html =~ ~s(<link rel="canonical" href="http://localhost:3000/">)
      assert html =~ "http://s3.test:8333/delivest/#{icon}/favicon.ico"
      assert html =~ "http://s3.test:8333/delivest/#{icon}/apple-touch-icon.png"

      assert html =~
               ~s(<meta property="og:image" content="http://s3.test:8333/delivest/#{share}">)

      assert html =~ ~s(<meta property="og:image:width" content="1200">)
      assert html =~ ~s(<meta name="twitter:card" content="summary_large_image">)
    end
  end

  test "noscript pixel appears only for the enabled branch public pages", %{conn: conn} do
    alias Delivest.Identity.Branch.BranchInfo
    alias Delivest.Repo

    enabled = insert(:branch, slug: "pixel-shop", is_active: true)
    disabled = insert(:branch, slug: "plain-shop", is_active: true)

    %BranchInfo{branch_id: enabled.id}
    |> BranchInfo.changeset(%{
      vk_ads: %{enabled: true, counter_id: "3817108", privacy_approved: true}
    })
    |> Repo.insert!()

    %BranchInfo{branch_id: disabled.id}
    |> BranchInfo.changeset(%{
      vk_ads: %{enabled: false, counter_id: "777", privacy_approved: true}
    })
    |> Repo.insert!()

    for path <- [
          "/pixel-shop",
          "/pixel-shop/promotions",
          "/pixel-shop/branch-info",
          "/pixel-shop/contacts",
          "/pixel-shop/legal/offer",
          "/pixel-shop/legal/terms",
          "/pixel-shop/legal/privacy",
          "/pixel-shop/legal/consent"
        ] do
      pixel =
        conn
        |> recycle()
        |> put_req_header("x-original-uri", path)
        |> get(~p"/seo/content")
        |> html_response(200)

      assert pixel =~ "counter?id=3817108;js=na"
      refute pixel =~ "777"
    end

    for path <- [
          "/plain-shop",
          "/pixel-shop/checkout",
          "/pixel-shop/legal/arbitrary",
          "/unknown-shop",
          "/"
        ] do
      response(
        conn |> recycle() |> put_req_header("x-original-uri", path) |> get(~p"/seo/content"),
        204
      )
    end
  end

  test "public product and category include the selected branch pixel and disabling clears it", %{
    conn: conn,
    admin: admin
  } do
    alias Delivest.{Identity, Relations, Repo}

    branch = insert(:branch, slug: "pixel-menu", is_active: true)
    category = insert(:category)
    {:ok, _} = Relations.create_relation(Repo, "Branch", branch.id, "Category", category.id)
    product = insert_branch_product(branch.id, category_id: category.id, slug: "pixel-product")

    {:ok, branch} =
      Identity.update_integrations(admin, branch, %{
        "vk_ads" => %{"enabled" => true, "counter_id" => "3817108", "privacy_approved" => true}
      })

    for path <- [
          "/pixel-menu/product/#{product.slug}",
          "/pixel-menu/category/#{category.id}"
        ] do
      html =
        conn
        |> recycle()
        |> put_req_header("x-original-uri", path)
        |> get(~p"/seo/content")
        |> html_response(200)

      assert html =~ "counter?id=3817108;js=na"
    end

    {:ok, _} = Identity.update_integrations(admin, branch, %{"vk_ads" => %{"enabled" => false}})

    html =
      conn
      |> recycle()
      |> put_req_header("x-original-uri", "/pixel-menu/product/#{product.slug}")
      |> get(~p"/seo/content")
      |> html_response(200)

    refute html =~ "top-fwz1.mail.ru"

    inactive = insert(:branch, slug: "inactive-pixel", is_active: false)

    {:ok, _} =
      Identity.update_integrations(admin, inactive, %{
        "vk_ads" => %{"enabled" => true, "counter_id" => "999", "privacy_approved" => true}
      })

    response(
      conn
      |> recycle()
      |> put_req_header("x-original-uri", "/inactive-pixel")
      |> get(~p"/seo/content"),
      204
    )
  end

  test "robots.txt closes private pages and points to the sitemap", %{conn: conn} do
    body = conn |> get(~p"/seo/robots.txt") |> text_response(200)

    assert body =~ "Disallow: /*/checkout"
    assert body =~ "Sitemap: http://localhost:3000/sitemap.xml"
  end

  test "sitemap.xml lists public pages of active branches", %{conn: conn} do
    insert(:branch, slug: "center", is_active: true)
    insert(:branch, slug: "closed", is_active: false)

    conn = get(conn, ~p"/seo/sitemaps/pages.xml")
    body = response(conn, 200)

    assert response_content_type(conn, :xml)
    assert body =~ "<loc>http://localhost:3000/center</loc>"
    assert body =~ "<loc>http://localhost:3000/center/promotions</loc>"
    refute body =~ "closed"
  end

  test "manifest and favicon follow the uploaded icon", %{conn: conn, admin: admin} do
    manifest = conn |> get(~p"/seo/site.webmanifest") |> response(200) |> Jason.decode!()
    assert %{"name" => "Delivest", "theme_color" => "#48010c", "icons" => [_, default]} = manifest
    assert default["src"] == "http://localhost:4000/images/seo/icon-512.png"

    assert redirected_to(get(conn, ~p"/seo/favicon.ico")) ==
             "http://localhost:4000/images/seo/favicon.ico"

    {:ok, %{icon_key: icon}} = Franchise.update_icon(admin, Delivest.S3Stub.png(512, 512))

    manifest = conn |> get(~p"/seo/site.webmanifest") |> response(200) |> Jason.decode!()
    assert [%{"sizes" => "192x192"}, %{"sizes" => "512x512", "src" => src}] = manifest["icons"]
    assert src == "http://s3.test:8333/delivest/#{icon}/icon-512.png"

    assert redirected_to(get(conn, ~p"/seo/favicon.ico")) ==
             "http://s3.test:8333/delivest/#{icon}/favicon.ico"
  end
end
