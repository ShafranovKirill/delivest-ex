defmodule DelivestWeb.Seo.SeoController do
  use DelivestWeb, :controller

  alias Delivest.Franchise
  alias DelivestWeb.Seo.{SeoHTML, SeoSite}

  def head(conn, _params) do
    site = SeoSite.build(Franchise.get_settings(), original_path(conn))
    html(conn, SeoHTML.head(site))
  end

  defp original_path(conn) do
    case get_req_header(conn, "x-original-uri") do
      ["/" <> _ = uri | _rest] -> URI.parse(uri).path || "/"
      _missing -> "/"
    end
  end
end
