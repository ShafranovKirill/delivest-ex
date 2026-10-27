defmodule Delivest.Integrations.YandexEda.OrderEvents do
  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.Integrations.YandexEda.Statuses
  alias Delivest.Oms.{Order, Orders}
  alias Delivest.Oms.OrderStatus, as: Progress

  def cancel(%Order{} = order, comment) do
    with {:ok, order} <- remote_status(order, "cancelled", %{"cancel_comment" => comment}) do
      cancel_locally(order, comment)
    end
  end

  def status(%Order{} = order, %{"status" => "CANCELLED"} = params),
    do: cancel(order, params["comment"] || params["reason"])

  def status(%Order{} = order, %{"status" => code}) do
    with {:ok, status} <- Statuses.from_yandex(code), do: remote_status(order, status, %{})
  end

  def status(_order, _params), do: {:error, :invalid_status}

  def courier(%Order{channel: channel} = order, params) do
    courier =
      params
      |> Map.take(["courier", "location", "maxPlaceArrivalTime"])
      |> Map.put("updated_at", DateTime.to_iso8601(DateTime.utc_now(:second)))

    Orders.update_order_channel(order, %{details: Map.put(channel.details, "courier", courier)})
  end

  defp remote_status(%Order{channel: channel} = order, status, details) do
    if forward?(channel.remote_status, status),
      do:
        Orders.update_order_channel(order, %{
          remote_status: status,
          remote_status_at: DateTime.utc_now(:second),
          details: Map.merge(channel.details, details)
        }),
      else: {:ok, order}
  end

  defp forward?(nil, _status), do: true

  defp forward?(current, status),
    do: Progress.forward?(String.to_existing_atom(current), String.to_existing_atom(status))

  defp cancel_locally(%Order{status: status} = order, _comment) when status in [:crm, :cancelled],
    do: {:ok, order}

  defp cancel_locally(%Order{} = order, comment) do
    Orders.update_order_details(order, %{
      "status" => "cancelled",
      "payment_method" => to_string(order.payment_method),
      "cancel_reason" => "other",
      "cancel_note" => cancel_note(comment)
    })
  end

  defp cancel_note(comment) when is_binary(comment) and comment != "",
    do: String.slice(gettext("Cancelled in Yandex Eda: %{comment}", comment: comment), 0, 300)

  defp cancel_note(_comment), do: gettext("Cancelled in Yandex Eda")
end
