defmodule Delivest.Push.StaffMessage do
  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.Oms.Order

  alias Delivest.Franchise

  def build(:order_created, order, branch),
    do:
      message(
        gettext("New order #%{number}", number: Order.short_number(order)),
        order,
        branch,
        :orders
      )

  def build(:order_ready, order, branch),
    do:
      message(
        gettext("Order #%{number} is ready", number: Order.short_number(order)),
        order,
        branch,
        :orders
      )

  def build(:channel_cancelled, order, branch),
    do:
      message(
        gettext("Order #%{number} was cancelled by the channel",
          number: Order.short_number(order)
        ),
        order,
        branch,
        :orders
      )

  def build(:delivery_requested, order, branch),
    do:
      message(
        gettext("New delivery request #%{number}", number: Order.short_number(order)),
        order,
        branch,
        :deliveries
      )

  def build(:delivery_assigned, order, branch),
    do:
      message(
        gettext("You were given order #%{number}", number: Order.short_number(order)),
        order,
        branch,
        :deliveries
      )

  defp message(body, order, branch, page) do
    settings = Franchise.get_settings()

    %{
      title: branch.name,
      body: body,
      icon: Franchise.icon_url(settings, "icon-192.png"),
      tag: "staff-#{page}-#{order.id}",
      url: url(page, branch, order)
    }
  end

  defp url(:orders, branch, order), do: "/staff/b/#{branch.slug}/orders?id=#{order.id}"
  defp url(:deliveries, branch, _order), do: "/staff/b/#{branch.slug}/deliveries"
end
