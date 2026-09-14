defmodule Delivest.Net.Catalogs do
  alias Delivest.Net
  alias Delivest.Net.MenuView

  def get_menu_for_branch(branch_id) do
    case Cachex.get(:menu_cache, branch_id) do
      {:ok, nil} ->
        raw_menu = Net.list_category_for_branch(branch_id, preload: [products: :media])
        processed_menu = MenuView.build(raw_menu)

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
end
