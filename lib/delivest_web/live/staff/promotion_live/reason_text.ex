defmodule DelivestWeb.Staff.PromotionLive.ReasonText do
  use Gettext, backend: DelivestWeb.Gettext

  alias DelivestWeb.Staff.OrderLive.OrderHelpers
  alias DelivestWeb.Staff.PromotionLive.RulesText

  def unmet(%{type: :subtotal, missing: missing}),
    do: gettext("add %{amount} more", amount: OrderHelpers.money(missing))

  def unmet(%{type: :quantity, missing: missing}),
    do: gettext("add %{count} more items", count: missing)

  def unmet(%{type: :product, name: name, missing: missing}),
    do: gettext("add «%{name}» × %{count}", name: name, count: missing)

  def unmet(%{type: :fulfillment, allowed: allowed}),
    do:
      gettext("only for: %{types}",
        types: Enum.map_join(allowed, ", ", &OrderHelpers.fulfillment_label/1)
      )

  def unmet(%{type: :time, from: from, to: to}),
    do: gettext("works from %{from} to %{to}", from: clock(from), to: clock(to))

  def unmet(%{type: :weekday, days: days}),
    do: gettext("works on: %{days}", days: Enum.map_join(days, ", ", &RulesText.weekday/1))

  def unmet(%{type: :requires_client}), do: gettext("needs the client's phone")
  def unmet(_reason), do: gettext("conditions are not met")

  def rejected(:not_found), do: gettext("Promo code not found")
  def rejected(:inactive), do: gettext("Promotion is turned off")
  def rejected(:not_started), do: gettext("Promotion has not started yet")
  def rejected(:expired), do: gettext("Promotion has ended")
  def rejected(:exhausted), do: gettext("Promotion usage limit is reached")
  def rejected(:requires_client), do: gettext("Enter the client's phone to use this code")
  def rejected(:client_limit), do: gettext("The client has already used this promotion")
  def rejected(:not_owner), do: gettext("This personal code belongs to another client")
  def rejected(:code_used), do: gettext("This code has already been used")
  def rejected(_reason), do: gettext("Promo code cannot be applied")

  defp clock(%Time{} = time), do: Calendar.strftime(time, "%H:%M")
end
