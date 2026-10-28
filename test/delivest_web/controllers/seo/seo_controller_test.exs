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
          "primary_color" => "#123456"
        })

      {:ok, %{icon_key: icon}} = Franchise.update_icon(admin, Delivest.S3Stub.png(512, 512))

      {:ok, %{share_image_key: share}} =
        Franchise.update_share_image(admin, Delivest.S3Stub.png(1200, 630))

      html = conn |> get(~p"/seo/head") |> html_response(200)

      assert html =~ "<title>Суши &lt;Like&gt;</title>"
      assert html =~ ~s(<meta name="description" content="Доставка роллов">)
      assert html =~ ~s(<meta name="theme-color" content="#123456">)
      assert html =~ ~s(<link rel="canonical" href="http://localhost:3000/">)
      assert html =~ "http://s3.test:8333/delivest/#{icon}/favicon.ico"
      assert html =~ "http://s3.test:8333/delivest/#{icon}/apple-touch-icon.png"

      assert html =~
               ~s(<meta property="og:image" content="http://s3.test:8333/delivest/#{share}">)

      assert html =~ ~s(<meta property="og:image:width" content="1200">)
      assert html =~ ~s(<meta name="twitter:card" content="summary_large_image">)
    end
  end

  test "robots.txt closes private pages and points to the sitemap", %{conn: conn} do
    body = conn |> get(~p"/seo/robots.txt") |> text_response(200)

    assert body =~ "Disallow: /*/checkout"
    assert body =~ "Sitemap: http://localhost:3000/sitemap.xml"
  end

  test "sitemap.xml lists public pages of active branches", %{conn: conn} do
    insert(:branch, slug: "center", is_active: true)
    insert(:branch, slug: "closed", is_active: false)

    conn = get(conn, ~p"/seo/sitemap.xml")
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
