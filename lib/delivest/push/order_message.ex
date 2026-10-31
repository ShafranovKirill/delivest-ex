defmodule Delivest.Push.OrderMessage do
  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.Oms.Order

  alias Delivest.{Franchise, Identity}

  @notified [:accepted, :preparing, :ready, :delivering, :completed, :cancelled]

  def notified?(status), do: status in @notified

  def build(order, status, contact, locale),
    do:
      localized(locale, fn ->
        message(order, body(status, order, contact), url(order, contact))
      end)

  def courier(order, contact, locale) do
    localized(locale, fn ->
      body =
        gettext("Courier %{name} is heading to pick up order %{number}",
          name: contact.name,
          number: Order.short_number(order)
        )

      message(order, body, url(order, contact))
    end)
  end

  def note(order, :card_only, locale) do
    localized(locale, fn ->
      body =
        gettext("The Yandex courier accepts only a card, pay for order %{number} by card",
          number: Order.short_number(order)
        )

      message(order, body, url(order))
    end)
  end

  defp localized(nil, fun), do: fun.()
  defp localized(locale, fun), do: Gettext.with_locale(DelivestWeb.Gettext, locale, fun)

  defp message(order, body, url) do
    settings = Franchise.get_settings()

    %{
      title: settings.name,
      body: body,
      icon: Franchise.icon_url(settings, "icon-192.png"),
      tag: "order-#{order.id}",
      url: url
    }
  end

  defp url(_order, %{tracking_url: url}) when is_binary(url), do: url
  defp url(order, _contact), do: url(order)

  defp url(order) do
    case Identity.get_branch(order.branch_id) do
      {:ok, branch} -> "/" <> branch.slug
      _ -> "/"
    end
  end

  defp body(:delivering, order, %{name: name}) when is_binary(name),
    do:
      gettext("Courier %{name} is on the way with order %{number}",
        name: name,
        number: Order.short_number(order)
      )

  defp body(status, order, _contact), do: body(status, order)

  defp body(:accepted, order),
    do: gettext("Order %{number} is confirmed", number: Order.short_number(order))

  defp body(:preparing, order),
    do: gettext("Order %{number} is being prepared", number: Order.short_number(order))

  defp body(:ready, %{fulfillment_type: :delivery} = order),
    do:
      gettext("Order %{number} is ready and will be on its way soon",
        number: Order.short_number(order)
      )

  defp body(:ready, %{fulfillment_type: :pickup} = order),
    do: gettext("Order %{number} is ready, you can pick it up", number: Order.short_number(order))

  defp body(:ready, order),
    do: gettext("Order %{number} is ready", number: Order.short_number(order))

  defp body(:delivering, order),
    do:
      gettext("The courier is on the way with order %{number}", number: Order.short_number(order))

  defp body(:completed, order),
    do:
      gettext("Order %{number} is completed. Enjoy your meal!", number: Order.short_number(order))

  defp body(:cancelled, order),
    do: gettext("Order %{number} was cancelled", number: Order.short_number(order))
end
