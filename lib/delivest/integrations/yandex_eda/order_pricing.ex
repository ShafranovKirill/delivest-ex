defmodule Delivest.Integrations.YandexEda.OrderPricing do
  alias Delivest.Integrations.YandexEda.OrderRequest
  alias Delivest.Promo.{Line, Result}

  def fixed(%OrderRequest{items: items, items_cost: items_cost}) do
    lines = Enum.map(items, &line/1)
    subtotal = lines |> Enum.map(& &1.total) |> Enum.sum()

    result = %Result{
      lines: lines,
      subtotal: subtotal,
      total: items_cost,
      discount: max(subtotal - items_cost, 0)
    }

    fn _cart, _attrs, _client_id -> {:ok, result} end
  end

  defp line(item) do
    %Line{
      key: item.product_id,
      product_id: item.product_id,
      name: item.name,
      base_price: div(item.total, item.quantity),
      quantity: item.quantity,
      total: item.total
    }
  end
end
