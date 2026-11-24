defmodule Delivest.Promo.MenuPrices do
  alias Delivest.Features
  alias Delivest.Promo.{Catalog, Compiled, Context, Eligibility, Selection, Strategy, Usage}
  alias Delivest.Promo.Effects.ProductPrices

  def overlay(categories, branch_id) when is_list(categories) do
    offers = branch_id |> sales(false) |> ProductPrices.offers_by_product()
    Enum.map(categories, &overlay_category(&1, offers))
  end

  def overlay_fresh(categories, branch_id) when is_list(categories) do
    offers = branch_id |> sales(true) |> ProductPrices.offers_by_product()
    Enum.map(categories, &overlay_category(&1, offers))
  end

  defp sales(branch_id, fresh?) do
    if Features.enabled?("promotions", {:branch, branch_id}),
      do: enabled_sales(branch_id, fresh?),
      else: []
  end

  defp enabled_sales(branch_id, fresh?) do
    candidates =
      branch_id
      |> then(fn id -> if fresh?, do: Catalog.list_uncached(id), else: Catalog.list(id) end)
      |> Catalog.refresh_products(branch_id)
      |> Enum.filter(&(Compiled.automatic?(&1) and Strategy.unconditional?(&1.strategy)))

    context = Context.new(branch_id: branch_id)
    usage = Usage.load_limited(Enum.map(candidates, & &1.promotion), nil, [], nil)

    candidates
    |> Enum.filter(&(Eligibility.check(&1.promotion, nil, context, usage) == :ok))
    |> Selection.pick()
  end

  defp overlay_category(category, offers) do
    Map.update(category, :products, [], fn products ->
      Enum.map(products || [], &overlay_product(&1, offers))
    end)
  end

  defp overlay_product(product, offers) do
    case ProductPrices.best(Map.get(offers, product.id, []), product.price) do
      nil -> Map.put(product, :old_price, nil)
      {price, _promotion_id} -> %{product | price: price} |> Map.put(:old_price, product.price)
    end
  end
end
