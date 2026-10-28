defmodule DelivestWeb.Staff.OrderLive.NextStep do
  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.Oms.OrderFlow

  def for_order(order, staff) do
    with to when not is_nil(to) <- OrderFlow.next(order),
         true <- OrderFlow.can?(order, to, {:staff, staff}) do
      {to, label(order, to)}
    else
      _ -> nil
    end
  end

  def label(_order, :accepted), do: gettext("Confirm")
  def label(_order, :preparing), do: gettext("Start cooking")
  def label(_order, :ready), do: gettext("Ready")
  def label(_order, :delivering), do: gettext("Hand to courier")
  def label(%{status: :ready}, :completed), do: gettext("Handed over")
  def label(_order, :completed), do: gettext("Delivered")
end
