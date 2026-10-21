defmodule DelivestWeb.Staff.PromotionLive.RulesText do
  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.Promo.Strategy
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  @weekdays %{1 => "mon", 2 => "tue", 3 => "wed", 4 => "thu", 5 => "fri", 6 => "sat", 7 => "sun"}

  def describe(%Strategy{} = strategy, names \\ %{}) do
    %{
      condition: strategy.condition && condition(strategy.condition, names),
      effects: Enum.map(strategy.effects, &effect(&1, names))
    }
  end

  def weekday(day), do: Map.fetch!(@weekdays, day)

  defp condition({:and, a, b}, names),
    do: "#{condition(a, names)} #{gettext("and")} #{condition(b, names)}"

  defp condition({:or, a, b}, names),
    do: "(#{condition(a, names)} #{gettext("or")} #{condition(b, names)})"

  defp condition({:not, a}, names),
    do: gettext("not (%{condition})", condition: condition(a, names))

  defp condition({:subtotal, op, value}, _names),
    do: gettext("cart total %{op} %{amount}", op: op, amount: OrderHelpers.money(value))

  defp condition({:quantity, op, value}, _names),
    do: gettext("items in cart %{op} %{count}", op: op, count: value)

  defp condition({:has, slug, quantity}, names),
    do: gettext("cart has «%{name}» × %{count}", name: name(names, slug), count: quantity)

  defp condition({:fulfillment, types}, _names),
    do:
      gettext("fulfillment: %{types}",
        types: Enum.map_join(types, ", ", &OrderHelpers.fulfillment_label/1)
      )

  defp condition({:time, from, to}, _names),
    do: gettext("from %{from} to %{to}", from: clock(from), to: clock(to))

  defp condition({:weekday, days}, _names),
    do: gettext("days: %{days}", days: Enum.map_join(days, ", ", &weekday/1))

  defp effect({:percent, percent, :cart, nil}, _names),
    do: gettext("%{percent}% off the cart", percent: percent)

  defp effect({:percent, percent, :cart, cap}, _names),
    do:
      gettext("%{percent}% off the cart, up to %{cap}",
        percent: percent,
        cap: OrderHelpers.money(cap)
      )

  defp effect({:percent, percent, {:products, slugs}, _cap}, names),
    do: gettext("%{percent}% off %{products}", percent: percent, products: names(names, slugs))

  defp effect({:amount, amount, :cart}, _names),
    do: gettext("%{amount} off the cart", amount: OrderHelpers.money(amount))

  defp effect({:amount, amount, {:products, slugs}}, names),
    do:
      gettext("%{amount} off each %{products}",
        amount: OrderHelpers.money(amount),
        products: names(names, slugs)
      )

  defp effect({:gift, slug, quantity}, names),
    do: gettext("gift: «%{name}» × %{count}", name: name(names, slug), count: quantity)

  defp effect({:price, slug, price}, names),
    do:
      gettext("«%{name}» for %{price}", name: name(names, slug), price: OrderHelpers.money(price))

  defp names(names, slugs), do: Enum.map_join(slugs, ", ", &"«#{name(names, &1)}»")

  defp name(names, slug), do: Map.get(names, slug, slug)

  defp clock(time), do: Calendar.strftime(time, "%H:%M")
end
