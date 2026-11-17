defmodule DelivestWeb.Seo.SitemapController do
  use DelivestWeb, :controller

  alias Delivest.Identity
  alias Delivest.Net.PublicOffers
  alias DelivestWeb.Seo.{Landing, SeoSite}

  def index(conn, _params) do
    entries =
      Identity.list_branches()
      |> Enum.flat_map(fn branch ->
        count = PublicOffers.sitemap_count(branch.id)

        products =
          if count > 0,
            do:
              for(
                page <- 0..div(count - 1, 1000),
                do:
                  "/sitemaps/#{URI.encode(branch.slug, &URI.char_unreserved?/1)}/products/#{page}.xml"
              ),
            else: []

        [
          "/sitemaps/#{URI.encode(branch.slug, &URI.char_unreserved?/1)}/categories.xml"
          | products
        ]
      end)

    xml(conn, [
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?><sitemapindex xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">",
      Enum.map(["/sitemaps/pages.xml" | entries], fn path ->
        ["<sitemap><loc>", Landing.escape(SeoSite.origin() <> path), "</loc></sitemap>"]
      end),
      "</sitemapindex>"
    ])
  end

  def pages(conn, _params) do
    slugs = Identity.list_branches() |> Enum.map(& &1.slug) |> Enum.filter(& &1)
    xml(conn, SeoSite.sitemap(slugs))
  end

  def categories(conn, %{"branch_slug" => slug}) do
    with {:ok, %{is_active: true} = branch} <- Identity.get_branch_by_slug(slug) do
      paths =
        Enum.map(
          PublicOffers.categories(branch.id),
          &PublicOffers.category_path(branch.slug, &1.id)
        )

      xml(conn, urlset(paths))
    else
      _ -> send_resp(conn, :not_found, "Not found")
    end
  end

  def products(conn, %{"branch_slug" => slug, "page_file" => file}) do
    with true <- String.ends_with?(file, ".xml"),
         {number, ".xml"} when number >= 0 and number <= 100_000 <- Integer.parse(file),
         {:ok, %{is_active: true} = branch} <- Identity.get_branch_by_slug(slug),
         [_ | _] = products <- PublicOffers.sitemap_products(branch.id, number) do
      xml(conn, urlset(Enum.map(products, &PublicOffers.product_path(branch.slug, &1))))
    else
      _ -> send_resp(conn, :not_found, "Not found")
    end
  end

  defp urlset(paths) do
    [
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?><urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">",
      Enum.map(paths, fn path ->
        ["<url><loc>", Landing.escape(SeoSite.origin() <> path), "</loc></url>"]
      end),
      "</urlset>"
    ]
  end

  defp xml(conn, data),
    do:
      conn
      |> put_resp_header("cache-control", "public, max-age=300")
      |> put_resp_content_type("application/xml")
      |> send_resp(200, IO.iodata_to_binary(data))
end
