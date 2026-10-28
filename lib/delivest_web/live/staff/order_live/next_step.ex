defmodule DelivestWeb.Staff.OrderLive.NextStep do
  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.Oms.{Kitchen, OrderFlow}

  def for_order(order, staff) do
    with to when not is_nil(to) <- OrderFlow.next(order),
         true <- OrderFlow.can?(order, to, {:staff, staff}) do
      {to, label(order, to)}
    else
      _ -> nil
    end
  end

  def label(_order, :accepted), do: gettext("Confirm")

  def label(order, :preparing) do
    if Kitchen.working?(order.branch_id),
      do: gettext("Send to the kitchen"),
      else: gettext("Start cooking")
  end

  def label(_order, :ready), do: gettext("Ready")
  def label(_order, :delivering), do: gettext("Hand to courier")
  def label(%{status: :ready}, :completed), do: gettext("Handed over")
  def label(_order, :completed), do: gettext("Delivered")
end
