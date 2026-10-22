defmodule DelivestWeb.Seo.SeoHTML do
  def head(site) do
    [
      [
        "<title>",
        Phoenix.HTML.html_escape(site.name) |> Phoenix.HTML.safe_to_string(),
        "</title>"
      ],
      meta(name: "description", content: site.description),
      tag("link", rel: "canonical", href: site.url),
      meta(name: "theme-color", content: site.color),
      site.favicon && tag("link", rel: "icon", href: site.favicon, sizes: "48x48"),
      tag("link", rel: "icon", type: "image/png", sizes: "32x32", href: site.icon_32),
      tag("link", rel: "apple-touch-icon", href: site.apple_touch_icon),
      tag("link", rel: "manifest", href: "/site.webmanifest"),
      meta(property: "og:type", content: "website"),
      meta(property: "og:locale", content: "ru_RU"),
      meta(property: "og:site_name", content: site.name),
      meta(property: "og:title", content: site.name),
      meta(property: "og:description", content: site.description),
      meta(property: "og:url", content: site.url),
      meta(property: "og:image", content: site.image),
      site.image_size && meta(property: "og:image:width", content: site.image_size.width),
      site.image_size && meta(property: "og:image:height", content: site.image_size.height),
      meta(name: "twitter:card", content: site.card)
    ]
    |> Enum.filter(& &1)
    |> Enum.map_join("\n", &IO.iodata_to_binary/1)
  end

  defp meta(attrs) do
    if attrs[:content], do: tag("meta", attrs)
  end

  defp tag(name, attrs),
    do: ["<", name, Phoenix.HTML.attributes_escape(attrs) |> Phoenix.HTML.safe_to_string(), ">"]
end
