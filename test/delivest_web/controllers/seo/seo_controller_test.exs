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
    test "falls back to the default logo before images are uploaded", %{conn: conn} do
      html =
        conn
        |> put_req_header("x-original-uri", "/center/promotions?utm_source=tg")
        |> get(~p"/seo/head")
        |> html_response(200)

      assert html =~ "<title>Delivest</title>"
      assert html =~ ~s(<link rel="canonical" href="http://localhost:3000/center/promotions">)

      assert html =~
               ~s(<meta property="og:image" content="http://localhost:3000/delivest-logo/logo-white.png">)

      assert html =~ ~s(<meta name="twitter:card" content="summary">)
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
end
