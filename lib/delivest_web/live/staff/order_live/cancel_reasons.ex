defmodule DelivestWeb.Staff.OrderLive.CancelReasons do
  use Gettext, backend: DelivestWeb.Gettext

  def selectable, do: [:customer_refused, :out_of_stock, :unreachable, :other]

  def label(:customer_refused), do: gettext("Customer refused")
  def label(:out_of_stock), do: gettext("Out of stock")
  def label(:unreachable), do: gettext("Could not reach the customer")
  def label(:client), do: gettext("Cancelled by the customer")
  def label(:not_paid), do: gettext("Not paid in time")
  def label(:not_confirmed), do: gettext("Not confirmed in time")
  def label(_reason), do: gettext("Other")
end
