defmodule DelivestWeb.Seo.SeoSite do
  alias Delivest.Franchise
  alias Delivest.Franchise.{Images, Settings}

  @default_icon "/delivest-logo/logo-white.png"

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

  def origin, do: Application.get_env(:delivest, :client_origin, "http://localhost:3000")
end
