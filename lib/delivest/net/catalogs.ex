defmodule Delivest.Net.Catalogs do
  alias Delivest.Net
  alias Delivest.Net.MenuView

  @cache :menu_cache
  @ttl :timer.hours(1)

  def get_menu_for_branch(branch_id) do
    case Ecto.UUID.cast(branch_id) do
      {:ok, uuid} -> fetch(uuid)
      :error -> {:error, :invalid_branch_id}
    end
  end

  def clear_menu_cache(branch_id) do
    Cachex.del(@cache, branch_id)
  end

  defp fetch(branch_id) do
    case Cachex.fetch(@cache, branch_id, fn id -> {:commit, build(id), ttl: @ttl} end) do
      {:ok, menu} -> {:ok, menu}
      {:commit, menu} -> {:ok, menu}
      {:commit, menu, _opts} -> {:ok, menu}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build(branch_id) do
    branch_id
    |> Net.list_category_for_branch(preload: [products: :media])
    |> MenuView.build()
  end
end
