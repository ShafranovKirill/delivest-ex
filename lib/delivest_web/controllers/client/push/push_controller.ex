defmodule DelivestWeb.Client.Push.PushController do
  use DelivestWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Delivest.{Oms, Push}
  alias DelivestWeb.Helpers.{ApiError, CookieHelper}
  alias DelivestWeb.Schemas.ErrorSchemas.ErrorResponse
  alias DelivestWeb.Schemas.PushSchemas.{PushKeyResponse, PushSubscriptionRequest}
  alias OpenApiSpex.Schema

  operation(:key,
    summary: "Ключ для push-уведомлений",
    description: "Публичный VAPID-ключ для подписки браузера на уведомления.",
    tags: ["Push"],
    responses: [ok: {"Ключ", "application/json", PushKeyResponse}]
  )

  def key(conn, _params), do: json(conn, %{data: %{public_key: Push.public_key()}})

  operation(:subscribe,
    summary: "Подписаться на статус заказа",
    description:
      "Сохраняет push-подписку браузера для активного заказа текущей сессии или клиента.",
    tags: ["Push"],
    parameters: [
      order_id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    request_body: {"Подписка браузера", "application/json", PushSubscriptionRequest},
    responses: [
      no_content: "Подписка сохранена",
      not_found: {"Заказ не найден", "application/json", ErrorResponse},
      unprocessable_entity: {"Неверная подписка", "application/json", ErrorResponse}
    ]
  )

  def subscribe(conn, %{"order_id" => order_id} = params) do
    with %Oms.Order{} = order <- owned_active_order(conn, order_id),
         {:ok, _subscription} <- Push.subscribe(order, subscription_attrs(params)) do
      send_resp(conn, :no_content, "")
    else
      nil ->
        ApiError.send_error(conn, :not_found, :order_not_found, "Order not found")

      {:error, _changeset} ->
        ApiError.send_error(
          conn,
          :unprocessable_entity,
          :invalid_subscription,
          "Invalid subscription"
        )
    end
  end

  defp owned_active_order(conn, order_id) do
    session_id = CookieHelper.get_cookie(conn, "session_id")

    session_id
    |> Oms.list_active_orders(client_id(conn.assigns.current_client))
    |> Enum.find(&(&1.id == order_id))
  end

  defp subscription_attrs(params) do
    keys = Map.get(params, "keys") || %{}

    %{
      endpoint: params["endpoint"],
      p256dh: keys["p256dh"],
      auth: keys["auth"],
      locale: params["locale"]
    }
  end

  defp client_id(nil), do: nil
  defp client_id(client), do: client.id
end
