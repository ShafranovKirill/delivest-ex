defmodule DelivestWeb.Seo.SeoController do
  use DelivestWeb, :controller

  alias Delivest.Franchise
  alias DelivestWeb.Seo.{Landing, SeoHTML, SeoSite}

  def head(conn, _params) do
    case Landing.resolve(original_path(conn)) do
      {:ok, landing} ->
        html(conn, SeoHTML.head(Landing.site(landing)))

      {:error, :not_found} ->
        send_resp(conn, :not_found, "Not found")

      :ordinary ->
        html(conn, SeoHTML.head(SeoSite.build(Franchise.get_settings(), original_path(conn))))
    end
  end

  def landing_status(conn, _params) do
    if Landing.exists?(original_path(conn)),
      do: send_resp(conn, :no_content, ""),
      else: send_resp(conn, :forbidden, "Not found")
  end

  def content(conn, _params) do
    case Landing.resolve(original_path(conn)) do
      {:ok, landing} -> html(conn, Landing.content(landing))
      {:error, :not_found} -> send_resp(conn, :not_found, "Not found")
      :ordinary -> send_resp(conn, :no_content, "")
    end
  end

  def robots(conn, _params) do
    conn
    |> cached()
    |> text(SeoSite.robots())
  end

  def sitemap(conn, _params), do: DelivestWeb.Seo.SitemapController.index(conn, %{})

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
