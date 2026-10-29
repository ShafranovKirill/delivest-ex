defmodule DelivestWeb.Staff.StaffPwaController do
  use DelivestWeb, :controller

  alias Delivest.Franchise
  use Gettext, backend: DelivestWeb.Gettext

  @worker Path.join(:code.priv_dir(:delivest), "pwa/staff-sw.js")
  @external_resource @worker
  @worker_source File.read!(@worker)

  def manifest(conn, _params) do
    settings = Franchise.get_settings()

    conn
    |> put_resp_header("cache-control", "public, max-age=300")
    |> put_resp_content_type("application/manifest+json")
    |> send_resp(200, Jason.encode!(manifest(settings)))
  end

  def worker(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header("service-worker-allowed", "/staff/")
    |> put_resp_content_type("application/javascript")
    |> send_resp(200, @worker_source)
  end

  defp manifest(settings) do
    name = settings.name || "Delivest"

    %{
      id: "/staff",
      name: gettext("%{name} staff", name: name),
      short_name: name,
      lang: "ru",
      start_url: "/staff",
      scope: "/staff/",
      display: "standalone",
      background_color: "#ffffff",
      theme_color: settings.primary_color || "#1f2937",
      icons: icons(settings)
    }
  end

  defp icons(settings) do
    for size <- [192, 512] do
      %{
        src: Franchise.icon_url(settings, "icon-#{size}.png") || "/images/seo/icon-#{size}.png",
        sizes: "#{size}x#{size}",
        type: "image/png",
        purpose: "any"
      }
    end
  end
end
