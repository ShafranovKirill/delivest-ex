defmodule Delivest.Integrations.YandexEda.OrderStatus do
  alias Delivest.Integrations.YandexEda.{Clock, Statuses}
  alias Delivest.Oms.{Order, Orders}
  alias Delivest.Oms.OrderFlow

  def report(%Order{} = order) do
    reported = reported(order)
    status = settle(reported, order.status)

    if status != reported,
      do:
        Orders.update_order_channel(order, %{
          details: Map.put(order.channel.details, "reported", status)
        })

    %{
      status: Statuses.to_yandex(status),
      comment: "",
      updatedAt: Clock.format(order.updated_at)
    }
  end

  defp reported(%Order{channel: %{details: %{"reported" => status}}}) when is_binary(status),
    do: String.to_existing_atom(status)

  defp reported(_order), do: nil

  defp settle(reported, current) do
    if OrderFlow.ahead?(reported, current), do: current, else: reported
  end
end
