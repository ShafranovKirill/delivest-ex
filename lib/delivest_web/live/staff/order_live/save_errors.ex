defmodule DelivestWeb.Staff.OrderLive.SaveErrors do
  use Gettext, backend: DelivestWeb.Gettext

  def message(:cart_is_empty), do: gettext("Cart is empty")
  def message(:product_unavailable), do: gettext("Some products are no longer available")
  def message(:client_blocked), do: gettext("This client is blocked")
  def message(:order_locked), do: gettext("CRM orders cannot be edited")
  def message(:awaiting_payment), do: gettext("The order is waiting for the online payment")
  def message(:order_finished), do: gettext("The order is finished")
  def message(:channel_order), do: gettext("The order came from a sales channel")
  def message(:crm_order), do: gettext("The CRM does not accept this change")
  def message(:with_courier), do: gettext("The order is with the courier")
  def message(:order_ready), do: gettext("The order is ready, the time cannot be changed")

  def message(:with_points),
    do: gettext("The order is paid with stars, the items cannot be changed")

  def message(:paid), do: gettext("The order is paid")
  def message(:refunded), do: gettext("The order has a refund")
  def message(:price_changed), do: gettext("Prices have changed, check the cart")

  def message(:promo_unavailable),
    do: gettext("The promotion has just run out, the cart was recalculated")

  def message(_reason), do: gettext("Failed to save order")
end
