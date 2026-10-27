defmodule Delivest.Push.OrderMessage do
  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.Franchise

  @notified [:accepted, :preparing, :ready, :delivering, :completed, :cancelled]

  def notified?(status), do: status in @notified

  def build(order, status, nil), do: message(order, status)

  def build(order, status, locale),
    do: Gettext.with_locale(DelivestWeb.Gettext, locale, fn -> message(order, status) end)

  defp message(order, status) do
    settings = Franchise.get_settings()

    %{
      title: settings.name,
      body: body(status, order),
      icon: Franchise.icon_url(settings, "icon-192.png"),
      tag: "order-#{order.id}",
      url: "/"
    }
  end

  defp body(:accepted, order),
    do: gettext("Order %{number} is confirmed", number: order.number)

  defp body(:preparing, order),
    do: gettext("Order %{number} is being prepared", number: order.number)

  defp body(:ready, %{fulfillment_type: :delivery} = order),
    do: gettext("Order %{number} is ready and will be on its way soon", number: order.number)

  defp body(:ready, %{fulfillment_type: :pickup} = order),
    do: gettext("Order %{number} is ready, you can pick it up", number: order.number)

  defp body(:ready, order), do: gettext("Order %{number} is ready", number: order.number)

  defp body(:delivering, order),
    do: gettext("The courier is on the way with order %{number}", number: order.number)

  defp body(:completed, order),
    do: gettext("Order %{number} is completed. Enjoy your meal!", number: order.number)

  defp body(:cancelled, order), do: gettext("Order %{number} was cancelled", number: order.number)
end
