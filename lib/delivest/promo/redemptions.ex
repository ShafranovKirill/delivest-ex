defmodule Delivest.Promo.Redemptions do
  import Ecto.Query, warn: false

  alias Delivest.Oms.Order
  alias Delivest.Promo.{Eligibility, PromoCode, Promotion, Redemption, Result, Usage}
  alias Delivest.Repo

  @spec replace(Order.t(), Result.t()) :: {:ok, [Redemption.t()]} | {:error, :promo_unavailable}
  def replace(%Order{} = order, %Result{applied: applied}) do
    Repo.delete_all(from(r in Redemption, where: r.order_id == ^order.id))
    record(order, applied)
  end

  def list_for_order(order_id),
    do: Repo.all(from(r in Redemption, where: r.order_id == ^order_id))

  defp record(_order, []), do: {:ok, []}

  defp record(order, applied) do
    promotions = lock_promotions(Enum.map(applied, & &1.promotion_id))
    codes = load_codes(applied)
    usage = Usage.load(Map.keys(promotions), order.client_id, Map.keys(codes), order.id)

    if Enum.all?(applied, &available?(&1, promotions, codes, order.client_id, usage)),
      do: {:ok, Enum.map(applied, &insert!(&1, order))},
      else: {:error, :promo_unavailable}
  end

  defp lock_promotions(ids) do
    from(p in Promotion, where: p.id in ^ids, lock: "FOR UPDATE")
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  defp load_codes(applied) do
    ids = for %{promo_code_id: id} when not is_nil(id) <- applied, do: id
    from(c in PromoCode, where: c.id in ^ids) |> Repo.all() |> Map.new(&{&1.id, &1})
  end

  defp available?(applied, promotions, codes, client_id, usage) do
    with %Promotion{deleted_at: nil, enabled: true} = promotion <-
           Map.get(promotions, applied.promotion_id),
         :ok <- Eligibility.limits(promotion, client_id, usage),
         :ok <- code_available(applied.promo_code_id, codes, usage) do
      true
    else
      _ -> false
    end
  end

  defp code_available(nil, _codes, _usage), do: :ok

  defp code_available(code_id, codes, usage) do
    case Map.get(codes, code_id) do
      %PromoCode{usage_limit: nil} ->
        :ok

      %PromoCode{usage_limit: limit} ->
        if Usage.code(usage, code_id) < limit, do: :ok, else: :used

      nil ->
        :missing
    end
  end

  defp insert!(applied, order) do
    Repo.insert!(%Redemption{
      promotion_id: applied.promotion_id,
      promo_code_id: applied.promo_code_id,
      order_id: order.id,
      client_id: order.client_id,
      discount: applied.discount
    })
  end
end
