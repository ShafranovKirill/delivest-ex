defmodule Delivest.Net.Catalogs do
  import Ecto.Query

  alias Delivest.Identity.Branch
  alias Delivest.Integrations.Channels
  alias Delivest.Net
  alias Delivest.Net.MenuView
  alias Delivest.Repo

  @cache :menu_cache
  @ttl :timer.hours(1)

  def get_menu_for_branch(branch_id) do
    case Ecto.UUID.cast(branch_id) do
      {:ok, uuid} -> fetch(uuid)
      :error -> {:error, :invalid_branch_id}
    end
  end

  def clear_menu_cache(branch_id) do
    bump_versions([branch_id])
    invalidate_menu_cache(branch_id)
  end

  def invalidate_menu_cache(branch_id) do
    safe_cache(fn -> Cachex.del(@cache, branch_id) end)
    Channels.menu_changed(branch_id)
    Phoenix.PubSub.broadcast(Delivest.PubSub, "branch_products:#{branch_id}", :catalog_changed)
    :ok
  end

  def clear_all_menu_cache do
    bump_all_versions()
    invalidate_all_menu_cache()
  end

  def invalidate_all_menu_cache do
    safe_cache(fn -> Cachex.clear(@cache) end)

    Repo.all(from b in Branch, select: b.id)
    |> Enum.each(fn branch_id ->
      Channels.menu_changed(branch_id)
      Phoenix.PubSub.broadcast(Delivest.PubSub, "branch_products:#{branch_id}", :catalog_changed)
    end)

    :ok
  end

  def bump_versions(branch_ids) do
    Repo.update_all(from(b in Branch, where: b.id in ^branch_ids), inc: [catalog_version: 1])
    :ok
  end

  def bump_all_versions do
    Repo.update_all(Branch, inc: [catalog_version: 1])
    :ok
  end

  defp fetch(branch_id) do
    version = Repo.one(from b in Branch, where: b.id == ^branch_id, select: b.catalog_version)
    key = {:branch_catalog, branch_id, version}

    case safe_cache(fn ->
           Cachex.fetch(@cache, key, fn _ -> {:commit, build(branch_id), ttl: @ttl} end)
         end) do
      {:ok, menu} -> {:ok, menu}
      {:commit, menu} -> {:ok, menu}
      _ -> {:ok, build(branch_id)}
    end
  end

  defp safe_cache(fun) do
    fun.()
  catch
    :exit, _reason -> {:error, :cache_unavailable}
  end

  defp build(branch_id) do
    branch_id
    |> Net.list_category_for_branch(preload: [products: :media])
    |> MenuView.build(Delivest.Net.ProductTags.menu_tags())
  end
end
