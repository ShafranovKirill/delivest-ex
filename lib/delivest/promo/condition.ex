defmodule Delivest.Promo.Condition do
  alias Delivest.Promo.{Compiled, Facts}

  @type reason :: %{required(:type) => atom(), optional(atom()) => term()}
  @type verdict :: :met | {:unmet, [reason()]} | {:unknown, [reason()]}

  @spec evaluate(Delivest.Promo.Strategy.condition() | nil, Facts.t(), Compiled.t()) :: verdict()
  def evaluate(nil, _facts, _compiled), do: :met

  def evaluate({:and, a, b}, facts, compiled),
    do: both(evaluate(a, facts, compiled), evaluate(b, facts, compiled))

  def evaluate({:or, a, b}, facts, compiled),
    do: either(evaluate(a, facts, compiled), evaluate(b, facts, compiled))

  def evaluate({:not, a}, facts, compiled) do
    case evaluate(a, facts, compiled) do
      :met -> {:unmet, [%{type: :other}]}
      {:unmet, _reasons} -> :met
      unknown -> unknown
    end
  end

  def evaluate({:subtotal, op, value}, facts, _compiled),
    do: compare(op, facts.subtotal, value, :subtotal)

  def evaluate({:quantity, op, value}, facts, _compiled),
    do: compare(op, facts.quantity, value, :quantity)

  def evaluate({:has, slug, quantity}, facts, compiled) do
    case Compiled.product(compiled, slug) do
      nil ->
        {:unmet, [%{type: :other}]}

      product ->
        missing = quantity - Map.get(facts.quantities, product.id, 0)

        if missing <= 0,
          do: :met,
          else:
            {:unmet,
             [%{type: :product, product_id: product.id, name: product.name, missing: missing}]}
    end
  end

  def evaluate({:fulfillment, allowed}, %Facts{fulfillment: nil}, _compiled),
    do: {:unknown, [%{type: :fulfillment, allowed: allowed}]}

  def evaluate({:fulfillment, allowed}, facts, _compiled),
    do: verdict(facts.fulfillment in allowed, %{type: :fulfillment, allowed: allowed})

  def evaluate({:time, from, to}, facts, _compiled),
    do: verdict(within?(facts.time, from, to), %{type: :time, from: from, to: to})

  def evaluate({:weekday, days}, facts, _compiled),
    do: verdict(facts.weekday in days, %{type: :weekday, days: days})

  defp both(:met, :met), do: :met
  defp both({:unmet, a}, {:unmet, b}), do: {:unmet, a ++ b}
  defp both({:unmet, a}, _b), do: {:unmet, a}
  defp both(_a, {:unmet, b}), do: {:unmet, b}
  defp both(a, b), do: {:unknown, reasons(a) ++ reasons(b)}

  defp either(:met, _b), do: :met
  defp either(_a, :met), do: :met
  defp either({:unknown, a}, _b), do: {:unknown, a}
  defp either(_a, {:unknown, b}), do: {:unknown, b}
  defp either({:unmet, a}, {:unmet, b}), do: {:unmet, Enum.min_by([a, b], &length/1)}

  defp reasons(:met), do: []
  defp reasons({_verdict, reasons}), do: reasons

  defp verdict(true, _reason), do: :met
  defp verdict(false, reason), do: {:unmet, [reason]}

  defp compare(op, actual, expected, type) do
    if holds?(op, actual, expected),
      do: :met,
      else: {:unmet, [shortage(op, actual, expected, type)]}
  end

  defp holds?(:>=, a, b), do: a >= b
  defp holds?(:>, a, b), do: a > b
  defp holds?(:<=, a, b), do: a <= b
  defp holds?(:<, a, b), do: a < b
  defp holds?(:=, a, b), do: a == b

  defp shortage(:>=, actual, expected, type), do: %{type: type, missing: expected - actual}
  defp shortage(:>, actual, expected, type), do: %{type: type, missing: expected - actual + 1}
  defp shortage(_op, _actual, _expected, _type), do: %{type: :other}

  defp within?(time, from, to) do
    if Time.compare(from, to) == :lt,
      do: Time.compare(time, from) != :lt and Time.compare(time, to) == :lt,
      else: Time.compare(time, from) != :lt or Time.compare(time, to) == :lt
  end
end
