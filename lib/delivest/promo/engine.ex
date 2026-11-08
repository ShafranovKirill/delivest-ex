defmodule Delivest.Promo.Engine do
  alias Delivest.Promo.{
    Basket,
    Catalog,
    Codes,
    Compiled,
    Condition,
    Context,
    Effects,
    Eligibility,
    Facts,
    FirstOrder,
    PromoCode,
    Result,
    Selection,
    Usage
  }

  @silent_rejections [:requires_client]

  @spec run([map()], Context.t()) :: Result.t()
  def run(items, %Context{} = context) do
    compiled =
      case {context.compiled_promotions, context.product_snapshot} do
        {entries, products} when is_list(entries) and is_map(products) ->
          by_slug = Map.new(products, fn {_id, product} -> {product.slug, product} end)
          Enum.map(entries, &%{&1 | products: by_slug})

        _ ->
          if(is_nil(context.catalog_version),
            do: Catalog.list(context.branch_id),
            else: Catalog.list(context.branch_id, context.catalog_version)
          )
          |> Catalog.refresh_products(context.branch_id)
      end

    automatic = Enum.filter(compiled, &Compiled.automatic?/1)
    {code_entry, code_state} = resolve_code(context, compiled)
    usage = load_usage(automatic, code_entry, context)
    basket = Basket.new(items)

    first_order_condition? =
      Enum.any?(compiled, &FirstOrder.condition?(&1.strategy.condition))

    facts = Facts.build(basket, context, first_order_condition?)

    existing =
      if context.source == "app" and context.client_id == context.authenticated_client_id,
        do: FirstOrder.existing_ids(context.except_order_id),
        else: MapSet.new()

    code_verdict = judge_code(code_entry, context, usage, facts, existing)
    auto_verdicts = Enum.map(automatic, &{&1, judge(&1, nil, context, usage, facts, existing)})

    selected = Selection.pick(eligible(code_entry, code_verdict) ++ eligible(auto_verdicts))

    basket
    |> Effects.apply(selected, context.promo_gifts)
    |> Result.build(
      selected,
      code_of(code_entry),
      hints(auto_verdicts),
      code_state(code_state, code_entry, code_verdict),
      context.promo_gifts
    )
  end

  defp resolve_code(%Context{code: nil}, _compiled), do: {nil, nil}

  defp resolve_code(%Context{code: code} = context, compiled) do
    case Codes.find(context.branch_id, code) do
      nil -> {nil, rejected(code, :not_found)}
      %PromoCode{} = promo_code -> attach_promotion(promo_code, compiled)
    end
  end

  defp attach_promotion(promo_code, compiled) do
    case Enum.find(compiled, &(&1.promotion.id == promo_code.promotion_id)) do
      nil -> {nil, rejected(promo_code.code, :inactive)}
      entry -> {{entry, promo_code}, nil}
    end
  end

  defp load_usage(automatic, code_entry, context) do
    Usage.load_limited(
      Enum.map(automatic, & &1.promotion) ++ code_promotions(code_entry),
      context.client_id,
      codes(code_entry),
      context.except_order_id
    )
  end

  defp code_promotions(nil), do: []
  defp code_promotions({entry, _code}), do: [entry.promotion]

  defp codes(nil), do: []
  defp codes({_entry, code}), do: [code]

  defp code_of(nil), do: nil
  defp code_of({_entry, code}), do: code

  defp judge_code(nil, _context, _usage, _facts, _existing), do: nil

  defp judge_code({entry, code}, context, usage, facts, existing),
    do: judge(entry, code, context, usage, facts, existing)

  defp judge(%Compiled{} = entry, code, context, usage, facts, existing) do
    facts =
      if MapSet.member?(existing, entry.promotion.id) and
           FirstOrder.required?(entry.strategy.condition),
         do: %{facts | first_order: true},
         else: facts

    case Eligibility.check(entry.promotion, code, context, usage) do
      :ok -> Condition.evaluate(entry.strategy.condition, facts, entry)
      {:error, reason} -> {:rejected, reason}
    end
  end

  defp eligible({entry, _code}, :met), do: [entry]
  defp eligible(_code_entry, _verdict), do: []

  defp eligible(verdicts), do: for({entry, :met} <- verdicts, do: entry)

  defp hints(verdicts) do
    Enum.flat_map(verdicts, fn
      {entry, {status, reasons}} when status in [:unmet, :unknown] ->
        actionable(entry, reasons)

      {entry, {:rejected, reason}} when reason in @silent_rejections ->
        [Result.hint(entry, [%{type: reason}])]

      _verdict ->
        []
    end)
  end

  defp actionable(entry, reasons) do
    if Enum.any?(reasons, &(&1.type in [:other, :first_order])),
      do: [],
      else: [Result.hint(entry, reasons)]
  end

  defp code_state(state, nil, _verdict), do: state

  defp code_state(nil, {entry, code}, verdict) do
    name = entry.promotion.name

    case verdict do
      :met -> Result.code_state(code.code, :applied, name: name)
      {:rejected, reason} -> Result.code_state(code.code, :rejected, name: name, reason: reason)
      {_status, reasons} -> Result.code_state(code.code, :pending, name: name, reasons: reasons)
    end
  end

  defp rejected(code, reason), do: Result.code_state(code, :rejected, reason: reason)
end
