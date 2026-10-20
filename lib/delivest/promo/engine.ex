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
    PromoCode,
    Result,
    Selection,
    Usage
  }

  @silent_rejections [:requires_client]

  @spec run([map()], Context.t()) :: Result.t()
  def run(items, %Context{} = context) do
    compiled = Catalog.list(context.branch_id)
    automatic = Enum.filter(compiled, &Compiled.automatic?/1)
    {code_entry, code_state} = resolve_code(context, compiled)
    usage = load_usage(automatic, code_entry, context)
    basket = Basket.new(items)
    facts = Facts.build(basket, context)

    code_verdict = judge_code(code_entry, context, usage, facts)
    auto_verdicts = Enum.map(automatic, &{&1, judge(&1, nil, context, usage, facts)})

    selected = Selection.pick(eligible(code_entry, code_verdict) ++ eligible(auto_verdicts))

    basket
    |> Effects.apply(selected)
    |> Result.build(
      selected,
      code_of(code_entry),
      hints(auto_verdicts),
      code_state(code_state, code_entry, code_verdict)
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
    promotions = Enum.map(automatic, & &1.promotion) ++ code_promotions(code_entry)
    code_ids = code_ids(code_entry)

    Usage.load(
      Enum.map(promotions, & &1.id),
      context.client_id,
      code_ids,
      context.except_order_id
    )
  end

  defp code_promotions(nil), do: []
  defp code_promotions({entry, _code}), do: [entry.promotion]

  defp code_ids(nil), do: []
  defp code_ids({_entry, code}), do: [code.id]

  defp code_of(nil), do: nil
  defp code_of({_entry, code}), do: code

  defp judge_code(nil, _context, _usage, _facts), do: nil

  defp judge_code({entry, code}, context, usage, facts),
    do: judge(entry, code, context, usage, facts)

  defp judge(%Compiled{} = entry, code, context, usage, facts) do
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
    if Enum.any?(reasons, &(&1.type == :other)), do: [], else: [Result.hint(entry, reasons)]
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
