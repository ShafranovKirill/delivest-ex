defmodule DelivestWeb.Seo.SeoController do
  use DelivestWeb, :controller

  alias Delivest.{Franchise, Identity}
  alias Delivest.Identity.Branch.VkAdsSettings
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
      {:ok, landing} ->
        html(conn, Landing.content(landing) <> pixel_noscript(landing.branch))

      {:error, :not_found} ->
        send_resp(conn, :not_found, "Not found")

      :ordinary ->
        case ordinary_public_branch(original_path(conn)) do
          {:ok, slug} ->
            case Identity.get_branch_by_slug(slug, preload: [:info]) do
              {:ok, %{is_active: true} = branch} ->
                case pixel_noscript(branch) do
                  "" -> send_resp(conn, :no_content, "")
                  markup -> html(conn, markup)
                end

              _ ->
                send_resp(conn, :no_content, "")
            end

          :error ->
            send_resp(conn, :no_content, "")
        end
    end
  end

  defp ordinary_public_branch(path) do
    case String.split(path, "/", trim: true) do
      [slug] ->
        {:ok, slug}

      [slug, section] when section in ~w(promotions branch-info contacts) ->
        {:ok, slug}

      [slug, "legal", document] when document in ~w(offer terms privacy consent) ->
        {:ok, slug}

      _ ->
        :error
    end
  end

  defp pixel_noscript(branch) do
    case Identity.get_branch(branch.id, preload: [:info]) do
      {:ok, %{is_active: true, info: info}} when not is_nil(info) ->
        config = VkAdsSettings.public_config(info.vk_ads)

        if config.enabled do
          id = Landing.escape(config.counter_id)

          ~s(<noscript><div><img src="https://top-fwz1.mail.ru/counter?id=#{id};js=na" referrerpolicy="origin" style="position:absolute;left:-9999px" alt="Top.Mail.Ru" /></div></noscript>)
        else
          ""
        end

      _ ->
        ""
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
