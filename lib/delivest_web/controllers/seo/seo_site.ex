defmodule DelivestWeb.Seo.SeoSite do
  alias Delivest.Franchise
  alias Delivest.Franchise.{Images, Settings}

  @default_icon "/delivest-logo/logo-white.png"
  @sitemap_pages ["", "/promotions", "/contacts", "/branch-info"]

  def build(%Settings{} = settings, path) do
    origin = origin()
    icon = &Franchise.icon_url(settings, &1)
    share_image = Franchise.share_image_url(settings)
    {width, height} = Images.share_size()

    %{
      name: settings.name,
      description: settings.description,
      color: settings.primary_color,
      url: origin <> path,
      favicon: icon.("favicon.ico"),
      icon_32: icon.("icon-32.png") || @default_icon,
      apple_touch_icon: icon.("apple-touch-icon.png") || @default_icon,
      image: share_image || icon.("icon-512.png") || origin <> @default_icon,
      image_size: if(share_image, do: %{width: width, height: height}),
      card: if(share_image, do: "summary_large_image", else: "summary")
    }
  end

  def manifest(%Settings{} = settings) do
    %{
      name: settings.name,
      short_name: settings.name,
      description: settings.description,
      lang: "ru",
      start_url: "/",
      scope: "/",
      display: "standalone",
      background_color: "#ffffff",
      theme_color: settings.primary_color,
      icons: manifest_icons(settings)
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp manifest_icons(%Settings{icon_key: nil}), do: []

  defp manifest_icons(settings) do
    for size <- [192, 512] do
      %{
        src: Franchise.icon_url(settings, "icon-#{size}.png"),
        sizes: "#{size}x#{size}",
        type: "image/png",
        purpose: "any"
      }
    end
  end

  def favicon(settings),
    do: Franchise.icon_url(settings, "favicon.ico") || origin() <> @default_icon

  def robots do
    """
    User-agent: *
    Disallow: /*/orders
    Disallow: /*/addresses
    Disallow: /*/checkout

    Sitemap: #{origin()}/sitemap.xml
    """
  end

  def sitemap(slugs) do
    urls =
      for slug <- slugs, page <- @sitemap_pages do
        ["  <url><loc>", origin(), "/", slug, page, "</loc></url>\n"]
      end

    IO.iodata_to_binary([
      ~s(<?xml version="1.0" encoding="UTF-8"?>\n),
      ~s(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n),
      urls,
      "</urlset>\n"
    ])
  end

  def origin, do: Application.get_env(:delivest, :client_origin, "http://localhost:3000")
end
