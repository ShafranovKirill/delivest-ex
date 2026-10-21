defmodule DelivestWeb.Client.Socket.SocketController do
  use DelivestWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias DelivestWeb.ClientToken
  alias DelivestWeb.Helpers.CookieHelper
  alias DelivestWeb.Schemas.SocketSchemas.SocketTokenResponse

  operation(:token,
    summary: "Токен для подключения к сокету",
    description:
      "Подключение: `/socket/websocket?token=...`. Каналы `orders` (событие `order`) и `auth:<confirmation_id>` (события `confirmed`, `failed`).",
    tags: ["Socket"],
    responses: [ok: {"Токен", "application/json", SocketTokenResponse}]
  )

  def token(conn, _params) do
    client_id = conn.assigns.current_client && conn.assigns.current_client.id
    token = ClientToken.issue_socket(session_id(conn), client_id)
    json(conn, %{data: %{token: token}})
  end

  defp session_id(conn) do
    case conn.resp_cookies do
      %{"session_id" => %{value: value}} -> value
      _ -> CookieHelper.get_cookie(conn, "session_id")
    end
  end
end
