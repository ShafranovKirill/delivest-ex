defmodule Delivest.Net.Catalogs do
  alias Delivest.Net

  def get_menu_for_branch(branch_id) do
    case Cachex.get(:menu_cache, branch_id) do
      {:ok, nil} ->
        menu = Net.list_category_for_branch(branch_id, preload: [:products])
        processed_menu = process_menu(menu)

        Cachex.put(:menu_cache, branch_id, processed_menu, ttl: :timer.hours(1))
        {:ok, processed_menu}

      {:ok, menu} ->
        {:ok, menu}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def clear_menu_cache(branch_id) do
    Cachex.del(:menu_cache, branch_id)
  end

  defp process_menu(menu) do
    Enum.map(menu, fn category ->
      processed_products =
        Enum.map(category.products, fn product ->
          url = Delivest.Media.get_url(product.media_id)

          product
          |> Map.delete(:media_id)
          |> Map.put(:photo_url, url)
        end)

      %{category | products: processed_products}
    end)
  end
end
