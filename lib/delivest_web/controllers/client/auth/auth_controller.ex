defmodule DelivestWeb.Client.Auth.AuthController do
  use DelivestWeb, :controller
  use OpenApiSpex.ControllerSpecs

  require Logger

  alias Delivest.Identity
  alias Delivest.Identity.PhoneConfirmations
  alias DelivestWeb.ClientToken
  alias DelivestWeb.Helpers.{ApiError, CookieHelper}
  alias DelivestWeb.Schemas.AuthSchemas
  alias DelivestWeb.Schemas.ErrorSchemas.ErrorResponse

  operation(:start,
    summary: "Запросить подтверждение номера звонком",
    description: "Клиент должен позвонить с указанного номера на `call_number`.",
    tags: ["Auth"],
    request_body: {"Номер телефона", "application/json", AuthSchemas.StartCallRequest},
    responses: [
      ok: {"Ожидается звонок", "application/json", AuthSchemas.StartCallResponse},
      unprocessable_entity: {"Некорректный номер", "application/json", ErrorResponse},
      service_unavailable: {"Сервис звонков недоступен", "application/json", ErrorResponse},
      too_many_requests: {"Слишком много запросов", "application/json", ErrorResponse}
    ]
  )

  def start(conn, params) do
    case Identity.start_client_auth(params["phone"], session_id(conn)) do
      {:ok, confirmation, call_number} ->
        render(conn, :start,
          confirmation: confirmation,
          call_number: call_number,
          expires_in: PhoneConfirmations.ttl_minutes() * 60
        )

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  operation(:complete,
    summary: "Проверить подтверждение и войти",
    description: "Пока звонка не было — 202 и `status: pending`. После звонка — токены.",
    tags: ["Auth"],
    parameters: [id: [in: :path, type: :string, description: "confirmation_id"]],
    responses: [
      ok: {"Номер подтверждён", "application/json", AuthSchemas.SessionResponse},
      accepted: {"Ожидается звонок", "application/json", AuthSchemas.SessionResponse},
      not_found: {"Подтверждение не найдено или истекло", "application/json", ErrorResponse},
      forbidden: {"Клиент заблокирован", "application/json", ErrorResponse}
    ]
  )

  def complete(conn, %{"id" => id}) do
    case Identity.complete_client_auth(id, session_id(conn)) do
      {:ok, client} ->
        render(conn, :session, client: client, tokens: ClientToken.issue(client.id))

      {:error, :pending} ->
        conn |> put_status(:accepted) |> render(:pending)

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  operation(:refresh,
    summary: "Обновить токены",
    tags: ["Auth"],
    request_body: {"Refresh-токен", "application/json", AuthSchemas.RefreshRequest},
    responses: [
      ok: {"Новые токены", "application/json", AuthSchemas.SessionResponse},
      unauthorized: {"Токен недействителен", "application/json", ErrorResponse},
      forbidden: {"Клиент заблокирован", "application/json", ErrorResponse}
    ]
  )

  def refresh(conn, params) do
    with token when is_binary(token) <- params["refresh_token"],
         {:ok, client_id} <- ClientToken.verify_refresh(token),
         {:ok, client} <- Identity.fetch_authenticated_client(client_id) do
      render(conn, :session, client: client, tokens: ClientToken.issue(client.id))
    else
      {:error, :client_blocked} -> render_error(conn, :client_blocked)
      _ -> render_error(conn, :invalid_refresh_token)
    end
  end

  defp session_id(conn), do: CookieHelper.get_cookie(conn, "session_id")

  defp render_error(conn, :invalid_phone),
    do: ApiError.send_error(conn, :unprocessable_entity, :invalid_phone, "Invalid phone")

  defp render_error(conn, :not_found),
    do: ApiError.send_error(conn, :not_found, :confirmation_not_found, "Confirmation not found")

  defp render_error(conn, :client_blocked),
    do: ApiError.send_error(conn, :forbidden, :client_blocked, "Client blocked")

  defp render_error(conn, :invalid_refresh_token),
    do: ApiError.send_error(conn, :unauthorized, :invalid_refresh_token, "Invalid refresh token")

  defp render_error(conn, reason) do
    Logger.error("Client auth failed: #{inspect(reason)}")
    ApiError.send_error(conn, :service_unavailable, :call_failed, "Failed to request a call")
  end
end
