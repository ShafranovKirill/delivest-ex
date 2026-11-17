defmodule DelivestWeb.Seo.Landing do
  @moduledoc "Public product/category content, identical for visitors and crawlers."

  alias Delivest.{Franchise, Identity}
  alias Delivest.Net.PublicOffers
  alias DelivestWeb.Seo.SeoSite

  def exists?(path) do
    with [slug, type, key] when type in ["product", "category"] <-
           String.split(path, "/", trim: true),
         {:ok, %{is_active: true} = branch} <- Identity.get_branch_by_slug(URI.decode(slug)) do
      case type do
        "product" -> PublicOffers.product_exists?(branch.id, URI.decode(key))
        "category" -> match?({:ok, _}, PublicOffers.category(branch.id, URI.decode(key)))
      end
    else
      _ -> false
    end
  end

  def resolve(path) do
    case String.split(path, "/", trim: true) do
      [slug, "product", key] -> product(URI.decode(slug), URI.decode(key))
      [slug, "category", key] -> category(URI.decode(slug), URI.decode(key))
      _ -> :ordinary
    end
  end

  def site(%{title: title, description: description, path: path} = landing) do
    site = SeoSite.build(Franchise.get_settings(), path)
    site = %{site | name: title, description: description}

    case landing do
      %{offer: %{photo_url: image}} when is_binary(image) ->
        %{site | image: image, image_size: nil}

      _ ->
        site
    end
  end

  def content(%{offer: offer, branch: branch}) do
    [
      "<section data-public-offer=\"",
      escape(offer.id),
      "\"><h1>",
      escape(offer.name),
      "</h1>",
      image(offer.photo_url, offer.name),
      "<p>",
      escape(offer.description),
      "</p><p>",
      money(offer.price),
      " RUB</p><p>",
      if(PublicOffers.purchasable?(offer), do: "В наличии", else: "Временно недоступно"),
      "</p><a href=\"/",
      escape(branch.slug),
      "\">Меню</a></section>"
    ]
    |> IO.iodata_to_binary()
  end

  def content(%{category: category, branch: branch, products: products}) do
    [
      "<section data-public-category=\"",
      escape(category.id),
      "\"><h1>",
      escape(category.name),
      "</h1><ul>",
      Enum.map(products, fn offer ->
        [
          "<li><a href=\"",
          escape(PublicOffers.product_path(branch.slug, offer)),
          "\">",
          escape(offer.name),
          "</a> ",
          money(offer.price),
          " RUB</li>"
        ]
      end),
      "</ul><a href=\"/",
      escape(branch.slug),
      "\">Меню</a></section>"
    ]
    |> IO.iodata_to_binary()
  end

  def money(kopecks) when is_integer(kopecks) do
    Integer.to_string(div(kopecks, 100)) <>
      "." <> String.pad_leading(Integer.to_string(rem(kopecks, 100)), 2, "0")
  end

  def escape(nil), do: ""

  def escape(value),
    do: value |> to_string() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  defp product(slug, key) do
    with {:ok, %{is_active: true} = branch} <- Identity.get_branch_by_slug(slug),
         {:ok, offer} <- PublicOffers.product(branch.id, key) do
      {:ok,
       %{
         branch: branch,
         offer: offer,
         title: offer.name,
         description: offer.description,
         path: PublicOffers.product_path(branch.slug, offer)
       }}
    else
      _ -> {:error, :not_found}
    end
  end

  defp category(slug, key) do
    with {:ok, %{is_active: true} = branch} <- Identity.get_branch_by_slug(slug),
         {:ok, category} <- PublicOffers.category(branch.id, key) do
      {:ok,
       %{
         branch: branch,
         category: category,
         products: PublicOffers.category_preview(branch.id, category.id),
         title: category.name,
         description: category.name,
         path: PublicOffers.category_path(branch.slug, category.id)
       }}
    else
      _ -> {:error, :not_found}
    end
  end

  defp image(nil, _name), do: []
  defp image(url, name), do: ["<img src=\"", escape(url), "\" alt=\"", escape(name), "\">"]
end
