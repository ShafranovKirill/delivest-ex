defmodule Delivest.Promo.Catalog do
  import Ecto.Query, warn: false

  require Logger

  alias Delivest.{Net, Repo}
  alias Delivest.Identity.Branch
  alias Delivest.Promo.{Compiled, Dsl, Promotion, Strategy}

  @cache :promo_cache
  @ttl :timer.minutes(10)

  @spec list(binary() | nil) :: [Compiled.t()]
  def list(nil), do: []

  def list(branch_id) do
    case Ecto.UUID.cast(branch_id) do
      {:ok, uuid} ->
        version = Repo.one(from b in Branch, where: b.id == ^uuid, select: b.catalog_version)
        cached(uuid, version)

      :error ->
        []
    end
  end

  def list(nil, _version), do: []

  def list(branch_id, version) do
    case Ecto.UUID.cast(branch_id) do
      {:ok, uuid} -> cached(uuid, version)
      :error -> []
    end
  end

  defp cached(branch_id, version) do
    key = {:compiled_promo, branch_id, version}

    result =
      try do
        Cachex.fetch(@cache, key, fn _key -> {:commit, load(branch_id), ttl: @ttl} end)
      catch
        :exit, _ -> {:error, :cache_unavailable}
      end

    case result do
      {:ok, compiled} -> compiled
      {:commit, compiled} -> compiled
      _ -> load(branch_id)
    end
  end

  def refresh_products(compiled, branch_id) do
    slugs = compiled |> Enum.flat_map(&Strategy.slugs(&1.strategy)) |> Enum.uniq()
    products = Net.list_branch_products_by_slugs(branch_id, slugs)
    Enum.map(compiled, &%{&1 | products: products})
  end

  def find(branch_id, promotion_id),
    do: Enum.find(list(branch_id), &(&1.promotion.id == promotion_id))

  def invalidate(branch_id) do
    Delivest.Net.Catalogs.clear_menu_cache(branch_id)
    Cachex.clear(:cart_cache)
  end

  def invalidate_after_commit(branch_id) do
    Delivest.Net.Catalogs.invalidate_menu_cache(branch_id)
    Cachex.clear(:cart_cache)
  end

  defp load(branch_id) do
    parsed = branch_id |> active() |> Repo.all() |> Enum.flat_map(&parse/1)

    Enum.map(parsed, fn {promotion, strategy} ->
      %Compiled{promotion: promotion, strategy: strategy}
    end)
  end

  defp active(branch_id) do
    from(p in Promotion,
      where: p.branch_id == ^branch_id and p.enabled and is_nil(p.deleted_at),
      order_by: [desc: p.priority, asc: p.inserted_at]
    )
  end

  defp parse(%Promotion{} = promotion) do
    case Dsl.parse(promotion.rules) do
      {:ok, strategy} ->
        [{promotion, strategy}]

      {:error, errors} ->
        Logger.warning("promotion #{promotion.id} has invalid rules: #{inspect(errors)}")
        []
    end
  end
end
