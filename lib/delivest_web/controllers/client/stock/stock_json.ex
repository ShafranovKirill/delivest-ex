defmodule DelivestWeb.Client.Stock.StockJSON do
  def index(%{stocks: stocks}) do
    %{data: for(stock <- stocks, do: stock_data(stock))}
  end

  defp stock_data(stock) do
    %{
      id: stock.id,
      description: stock.text,
      is_active: stock.is_active,
      media: render_media(stock.media)
    }
  end

  defp render_media(%Ecto.Association.NotLoaded{}), do: nil
  defp render_media(nil), do: nil

  defp render_media(media) do
    %{
      id: media.id,
      url: Delivest.Media.get_url_from_file(media)
    }
  end
end
