defmodule Delivest.Integrations.YandexEda.OrderEvents do
  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.Integrations.YandexEda.Statuses
  alias Delivest.Oms.{Order, OrderFlow, Orders}

  def cancel(%Order{} = order, comment) do
    remote_status(order, "cancelled", %{"cancel_comment" => comment},
      attrs: %{cancel_reason: :other, cancel_note: cancel_note(comment)},
      reason: cancel_note(comment)
    )
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

  def feedback(%Order{channel: channel} = order, feedback) do
    review = %{
      "id" => feedback["id"],
      "rating" => feedback["rating"],
      "comment" => feedback["comment"],
      "predefined_comment" => feedback["predefinedComment"],
      "created_at" => feedback["createdAt"]
    }

    Orders.update_order_channel(order, %{details: Map.put(channel.details, "feedback", review)})
  end

  defp remote_status(%Order{channel: channel} = order, status, details, opts \\ []) do
    if forward?(channel.remote_status, status) do
      channel = %{
        remote_status: status,
        remote_status_at: DateTime.utc_now(:second),
        details: Map.merge(channel.details, details)
      }

      Orders.advance_order(
        order,
        String.to_existing_atom(status),
        :channel,
        Keyword.put(opts, :with, &Order.channel_changeset(&1, channel))
      )
    else
      {:ok, order}
    end
  end

  defp forward?(nil, _status), do: true

  defp forward?(current, status),
    do: OrderFlow.ahead?(String.to_existing_atom(current), String.to_existing_atom(status))

  defp cancel_note(comment) when is_binary(comment) and comment != "",
    do: String.slice(gettext("Cancelled in Yandex Eda: %{comment}", comment: comment), 0, 300)

  defp cancel_note(_comment), do: gettext("Cancelled in Yandex Eda")
end
