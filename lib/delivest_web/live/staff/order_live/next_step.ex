defmodule DelivestWeb.Staff.OrderLive.NextStep do
  use Gettext, backend: DelivestWeb.Gettext

  def for_order(%{status: :created}), do: {:preparing, gettext("Accept")}
  def for_order(%{status: :preparing}), do: {:ready, gettext("Ready")}

  def for_order(%{status: :ready, fulfillment_type: :delivery}),
    do: {:delivering, gettext("Hand to courier")}

  def for_order(%{status: :ready}), do: {:completed, gettext("Handed over")}
  def for_order(%{status: :delivering}), do: {:completed, gettext("Delivered")}
  def for_order(_order), do: nil
end
