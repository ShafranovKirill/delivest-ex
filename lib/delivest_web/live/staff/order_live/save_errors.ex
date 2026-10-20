defmodule DelivestWeb.Staff.OrderLive.SaveErrors do
  use Gettext, backend: DelivestWeb.Gettext

  def message(:cart_is_empty), do: gettext("Cart is empty")
  def message(:product_unavailable), do: gettext("Some products are no longer available")
  def message(:client_blocked), do: gettext("This client is blocked")
  def message(:order_locked), do: gettext("CRM orders cannot be edited")
  def message(:price_changed), do: gettext("Prices have changed, check the cart")

  def message(:promo_unavailable),
    do: gettext("The promotion has just run out, the cart was recalculated")

  def message(_reason), do: gettext("Failed to save order")
end
