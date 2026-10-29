defmodule DelivestWeb.Staff.OrderLive.OrderHelpers do
  use Gettext, backend: DelivestWeb.Gettext

  def status_color(status) when is_atom(status), do: status_color(Atom.to_string(status))
  def status_color("created"), do: "bg-info/10 text-info border-info/20"
  def status_color("accepted"), do: "bg-primary/10 text-primary border-primary/20"
  def status_color("preparing"), do: "bg-warning/10 text-warning border-warning/20"
  def status_color("ready"), do: "bg-accent/10 text-accent border-accent/20"
  def status_color("delivering"), do: "bg-secondary/10 text-secondary border-secondary/20"
  def status_color("completed"), do: "bg-success/10 text-success border-success/20"
  def status_color("cancelled"), do: "bg-error/10 text-error border-error/20"
  def status_color(_), do: "bg-base-200 text-base-content border-base-300"

  def status_dot(status) when is_atom(status), do: status_dot(Atom.to_string(status))
  def status_dot("created"), do: "bg-info"
  def status_dot("accepted"), do: "bg-primary"
  def status_dot("preparing"), do: "bg-warning"
  def status_dot("ready"), do: "bg-accent"
  def status_dot("delivering"), do: "bg-secondary"
  def status_dot("completed"), do: "bg-success"
  def status_dot("cancelled"), do: "bg-error"
  def status_dot(_), do: "bg-base-300"

  def status_label(status) when is_atom(status), do: status_label(Atom.to_string(status))
  def status_label("created"), do: gettext("Created")
  def status_label("accepted"), do: gettext("Confirmed")
  def status_label("preparing"), do: gettext("Preparing")
  def status_label("ready"), do: gettext("Ready")
  def status_label("delivering"), do: gettext("Delivering")
  def status_label("completed"), do: gettext("Completed")
  def status_label("cancelled"), do: gettext("Cancelled")
  def status_label(other), do: to_string(other)

  def fulfillment_label(type) when is_atom(type) and not is_nil(type),
    do: fulfillment_label(Atom.to_string(type))

  def fulfillment_label("delivery"), do: gettext("Delivery")
  def fulfillment_label("dine_in"), do: gettext("Dine in")
  def fulfillment_label("pickup"), do: gettext("Pickup")
  def fulfillment_label(_), do: "—"

  def payment_label(method) when is_atom(method) and not is_nil(method),
    do: payment_label(Atom.to_string(method))

  def payment_label("cash"), do: gettext("Cash")
  def payment_label("card_offline"), do: gettext("Card Offline")
  def payment_label("online"), do: gettext("Paid online")
  def payment_label(_), do: "—"

  def format_address(%Delivest.Oms.Order.Address{} = addr) do
    [
      addr.city,
      addr.street,
      addr.house && "#{gettext("d.")} #{Delivest.Oms.Order.Address.house_line(addr)}",
      addr.entrance && "#{gettext("ent.")} #{addr.entrance}",
      addr.floor && "#{gettext("fl.")} #{addr.floor}",
      addr.apartment && "#{gettext("apt.")} #{addr.apartment}",
      addr.intercom && "#{gettext("code")} #{addr.intercom}",
      addr.comment
    ]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(", ")
  end

  def format_address(_address), do: "—"

  defdelegate money(amount), to: Delivest.Money, as: :format

  def local_datetime(nil), do: "—"

  def local_datetime(%DateTime{} = dt) do
    dt
    |> DateTime.shift_zone!(Delivest.LocalTime.timezone())
    |> Calendar.strftime("%d.%m.%Y %H:%M")
  end

  def local_time(%DateTime{} = dt) do
    dt |> DateTime.shift_zone!(Delivest.LocalTime.timezone()) |> Calendar.strftime("%H:%M")
  end
end
