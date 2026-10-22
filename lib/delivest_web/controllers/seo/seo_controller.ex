defmodule DelivestWeb.Seo.SeoController do
  use DelivestWeb, :controller

  alias Delivest.{Franchise, Identity}
  alias DelivestWeb.Seo.{SeoHTML, SeoSite}

  def head(conn, _params) do
    site = SeoSite.build(Franchise.get_settings(), original_path(conn))
    html(conn, SeoHTML.head(site))
  end

  def robots(conn, _params) do
    conn
    |> cached()
    |> text(SeoSite.robots())
  end

  def sitemap(conn, _params) do
    slugs = Identity.list_branches() |> Enum.map(& &1.slug) |> Enum.filter(& &1)

    conn
    |> cached()
    |> put_resp_content_type("application/xml")
    |> send_resp(200, SeoSite.sitemap(slugs))
  end

  def manifest(conn, _params) do
    conn
    |> cached()
    |> put_resp_content_type("application/manifest+json")
    |> send_resp(200, Jason.encode!(SeoSite.manifest(Franchise.get_settings())))
  end

  def favicon(conn, _params) do
    conn
    |> cached()
    |> redirect(external: SeoSite.favicon(Franchise.get_settings()))
  end

  defp cached(conn), do: put_resp_header(conn, "cache-control", "public, max-age=300")

  defp original_path(conn) do
    case get_req_header(conn, "x-original-uri") do
      ["/" <> _ = uri | _rest] -> URI.parse(uri).path || "/"
      _missing -> "/"
    end
  end
end
