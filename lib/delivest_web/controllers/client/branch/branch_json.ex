defmodule DelivestWeb.Client.Branch.BranchJSON do
  def index(%{branches: branches}) do
    %{data: for(branch <- branches, do: branch_data(branch))}
  end

  def show(%{branch: branch}) do
    %{data: branch_data(branch)}
  end

  defp branch_data(branch) do
    %{
      id: branch.id,
      name: branch.name,
      slug: branch.slug,
      is_active: branch.is_active,
      branch_info: branch_info(branch.info),
      stocks: stocks_data(branch.stocks)
    }
  end

  defp branch_info(%Ecto.Association.NotLoaded{}), do: nil
  defp branch_info(nil), do: nil

  defp branch_info(info) do
    %{
      id: info.id,
      address: info.address,
      phone_number: info.phone_number,
      vk_url: info.vk_url,
      whatsapp_url: info.whatsapp_url,
      instagram_url: info.instagram_url
    }
  end

  defp stocks_data(%Ecto.Association.NotLoaded{}), do: []
  defp stocks_data(nil), do: []

  defp stocks_data(stocks) when is_list(stocks) do
    Enum.map(stocks, &stock_data/1)
  end

  defp stock_data(stock) do
    %{
      id: stock.id,
      description: stock.text,
      photo_url: Delivest.Media.get_url(stock.media_id),
      is_active: stock.is_active
    }
  end
end
