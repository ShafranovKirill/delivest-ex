defmodule Delivest.Promo.Catalog do
  import Ecto.Query, warn: false

  require Logger

  alias Delivest.{Net, Repo}
  alias Delivest.Promo.{Compiled, Dsl, Promotion, Strategy}

  @cache :promo_cache
  @ttl :timer.minutes(10)

  @spec list(binary() | nil) :: [Compiled.t()]
  def list(nil), do: []

  def list(branch_id) do
    case Ecto.UUID.cast(branch_id) do
      {:ok, uuid} -> cached(uuid)
      :error -> []
    end
  end

  defp cached(branch_id) do
    case Cachex.fetch(@cache, branch_id, fn _key -> {:commit, load(branch_id), ttl: @ttl} end) do
      {:ok, compiled} -> compiled
      {:commit, compiled} -> compiled
      {:commit, compiled, _opts} -> compiled
      _ -> load(branch_id)
    end
  end

  def find(branch_id, promotion_id),
    do: Enum.find(list(branch_id), &(&1.promotion.id == promotion_id))

  def invalidate(branch_id) do
    Cachex.del(@cache, branch_id)
    Cachex.clear(:cart_cache)
  end

  defp load(branch_id) do
    parsed = branch_id |> active() |> Repo.all() |> Enum.flat_map(&parse/1)
    slugs = parsed |> Enum.flat_map(fn {_promotion, strategy} -> Strategy.slugs(strategy) end)
    products = Net.list_branch_products_by_slugs(branch_id, Enum.uniq(slugs))

    Enum.map(parsed, fn {promotion, strategy} ->
      %Compiled{promotion: promotion, strategy: strategy, products: products}
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
