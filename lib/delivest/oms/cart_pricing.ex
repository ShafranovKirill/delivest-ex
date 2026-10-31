defmodule Delivest.Oms.CartPricing do
  alias Delivest.Oms.CartView
  alias Delivest.Promo

  def apply(%CartView{} = view, overrides \\ []) do
    result = Promo.price(CartView.base_items(view), context(view, overrides))
    result = Delivest.Loyalty.Earnings.price(result, view.branch_id)
    CartView.with_pricing(view, result)
  end

  def context(%CartView{} = view, overrides \\ []) do
    Map.merge(
      %{
        branch_id: view.branch_id,
        client_id: view.client_id,
        fulfillment_type: view.fulfillment_type,
        code: view.promo_code
      },
      Map.new(overrides)
    )
  end
end
