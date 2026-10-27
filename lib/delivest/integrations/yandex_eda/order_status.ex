defmodule Delivest.Integrations.YandexEda.OrderStatus do
  alias Delivest.Integrations.YandexEda.{Clock, Statuses}
  alias Delivest.Oms.{Order, Orders}
  alias Delivest.Oms.OrderStatus, as: Progress

  def report(%Order{} = order) do
    reported = reported(order)
    status = reported |> settle(Progress.current(order))

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
    if is_nil(reported) or Progress.forward?(reported, current), do: current, else: reported
  end
end
