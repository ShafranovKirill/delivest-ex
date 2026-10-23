defmodule DelivestWeb.Client.Stock.StockJSON do
  def index(%{stocks: stocks}) do
    %{data: for(stock <- stocks, do: stock_data(stock))}
  end

  defp stock_data(stock) do
    %{
      id: stock.id,
      text: stock.text,
      is_active: stock.is_active,
      order: stock.order,
      photo_url: render_media(stock.media),
      product_slug: product_slug(stock.product)
    }
  end

  defp product_slug(%Delivest.Net.Product{is_active: true, deleted_at: nil, slug: slug}), do: slug
  defp product_slug(_), do: nil

  defp render_media(%Ecto.Association.NotLoaded{}), do: nil
  defp render_media(nil), do: nil

  defp render_media(media) do
    Delivest.Media.thumb_url_from_file(media)
  end
end
