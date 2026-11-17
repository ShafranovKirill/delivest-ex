defmodule DelivestWeb.Seo.CatalogController do
  use DelivestWeb, :controller

  alias Delivest.{Franchise, Identity}
  alias Delivest.Integrations.YandexAds
  alias Delivest.Net.PublicOffers
  alias DelivestWeb.Seo.{Landing, SeoSite}

  def show(conn, %{"branch_slug" => slug}) do
    with {:ok, %{is_active: true} = branch} <- Identity.get_branch_by_slug(slug),
         true <- YandexAds.enabled?(:feed, branch.id) do
      stream(conn, branch)
    else
      _ -> send_resp(conn, :not_found, "Not found")
    end
  end

  def offer_xml(branch, category_id, offer) do
    [
      "<offer id=\"",
      Landing.escape(offer.id),
      "\" available=\"",
      to_string(PublicOffers.purchasable?(offer)),
      "\">",
      tag("url", SeoSite.origin() <> PublicOffers.product_path(branch.slug, offer)),
      tag("price", Landing.money(offer.price)),
      tag("currencyId", "RUB"),
      tag("categoryId", category_id),
      tag("name", offer.name),
      if(offer.photo_url, do: tag("picture", offer.photo_url), else: []),
      if(offer.description, do: tag("description", offer.description), else: []),
      if(offer.old_price && offer.old_price > offer.price,
        do: tag("oldprice", Landing.money(offer.old_price)),
        else: []
      ),
      "</offer>\n"
    ]
  end

  defp stream(conn, branch) do
    settings = Franchise.get_settings()

    conn =
      conn
      |> put_resp_content_type("application/xml")
      |> put_resp_header("cache-control", "no-store")
      |> send_chunked(200)

    opening = [
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?><yml_catalog date=\"",
      Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M"),
      "\"><shop>",
      tag("name", settings.name || "Delivest"),
      tag("company", settings.name || "Delivest"),
      tag("url", SeoSite.origin() <> "/" <> branch.slug),
      "<currencies><currency id=\"RUB\" rate=\"1\"/></currencies><categories>",
      Enum.map(PublicOffers.categories(branch.id), fn c ->
        ["<category id=\"", Landing.escape(c.id), "\">", Landing.escape(c.name), "</category>"]
      end),
      "</categories><offers>"
    ]

    with {:ok, conn} <- chunk(conn, opening) do
      result =
        Enum.reduce_while(PublicOffers.batches(branch.id), {:ok, conn}, fn categories,
                                                                           {:ok, conn} ->
          if YandexAds.enabled?(:feed, branch.id) do
            data =
              for category <- categories,
                  offer <- category.products,
                  do: offer_xml(branch, category.id, offer)

            case chunk(conn, data) do
              {:ok, conn} -> {:cont, {:ok, conn}}
              {:error, _} -> {:halt, {:stopped, conn}}
            end
          else
            {:halt, {:stopped, conn}}
          end
        end)

      case result do
        {:ok, conn} ->
          case chunk(conn, "</offers></shop></yml_catalog>") do
            {:ok, conn} -> conn
            _ -> conn
          end

        {:stopped, conn} ->
          conn
      end
    else
      _ -> conn
    end
  end

  defp tag(name, value), do: ["<", name, ">", Landing.escape(value), "</", name, ">"]
end
