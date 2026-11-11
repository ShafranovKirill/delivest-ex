defmodule DelivestWeb.Client.Notifications.NotificationController do
  use DelivestWeb, :controller
  use OpenApiSpex.ControllerSpecs
  alias Delivest.Notifications
  alias DelivestWeb.Helpers.ApiError
  alias DelivestWeb.Schemas.ErrorSchemas.ErrorResponse

  alias DelivestWeb.Schemas.NotificationSchemas.{
    ClickResponse,
    ConsentRequest,
    ConsentResponse,
    ListResponse
  }

  alias OpenApiSpex.Schema

  @branch [in: :query, schema: %Schema{type: :string, format: :uuid}, required: true]
  @device [in: :query, schema: %Schema{type: :string, format: :uuid}, required: true]
  @id [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
  @action_body %Schema{
    type: :object,
    properties: %{
      branch_id: %Schema{type: :string, format: :uuid},
      device_id: %Schema{type: :string, format: :uuid}
    },
    required: [:branch_id, :device_id]
  }

  operation(:index,
    summary: "Карточки клиента для текущего филиала и устройства",
    description:
      "Только канал in_app. Просмотр не закрывает карточку. Курсор проходит и через устаревшие карточки.",
    tags: ["Notifications"],
    security: [%{"bearer" => []}],
    parameters: [
      branch_id: @branch,
      device_id: @device,
      cursor: [in: :query, schema: %Schema{type: :string}]
    ],
    responses: [
      ok: {"Карточки", "application/json", ListResponse},
      not_found: {"Модуль выключен", "application/json", ErrorResponse},
      unprocessable_entity: {"Неверный курсор или устройство", "application/json", ErrorResponse}
    ]
  )

  def index(conn, params) do
    with {:ok, data} <-
           Notifications.list(
             client_id(conn),
             params["branch_id"],
             device_id(conn, params),
             params["cursor"]
           ) do
      json(conn, %{data: Enum.map(data.items, &render_notice/1), next_cursor: data.next_cursor})
    else
      error -> render_error(conn, error)
    end
  end

  operation(:dismiss,
    summary: "Закрыть карточку на одном устройстве",
    tags: ["Notifications"],
    security: [%{"bearer" => []}],
    parameters: [id: @id],
    request_body: {"Устройство и филиал", "application/json", @action_body},
    responses: [
      no_content: "Закрыто",
      not_found: {"Не найдено", "application/json", ErrorResponse},
      unprocessable_entity: {"Неверный запрос", "application/json", ErrorResponse}
    ]
  )

  def dismiss(conn, %{"id" => id} = params) do
    case Notifications.dismiss(client_id(conn), params["branch_id"], device_id(conn, params), id) do
      :ok -> send_resp(conn, :no_content, "")
      error -> render_error(conn, error)
    end
  end

  operation(:click,
    summary: "Отметить переход из текущей карточки",
    tags: ["Notifications"],
    security: [%{"bearer" => []}],
    parameters: [id: @id],
    request_body: {"Устройство и филиал", "application/json", @action_body},
    responses: [
      ok: {"Действие", "application/json", ClickResponse},
      not_found: {"Не найдено или истекло", "application/json", ErrorResponse},
      unprocessable_entity: {"Неверный запрос", "application/json", ErrorResponse}
    ]
  )

  def click(conn, %{"id" => id} = params) do
    case Notifications.click(client_id(conn), params["branch_id"], device_id(conn, params), id) do
      {:ok, cta} -> json(conn, %{data: cta})
      error -> render_error(conn, error)
    end
  end

  operation(:consents,
    summary: "Маркетинговые согласия и доступность каналов",
    tags: ["Notifications"],
    security: [%{"bearer" => []}],
    parameters: [branch_id: @branch],
    responses: [
      ok: {"Согласия", "application/json", ConsentResponse},
      not_found: {"Модуль выключен", "application/json", ErrorResponse}
    ]
  )

  def consents(conn, params) do
    case Notifications.consents(client_id(conn), params["branch_id"]) do
      {:ok, data} ->
        json(conn, %{data: data, capabilities: %{in_app: true, push: true, sms: false}})

      error ->
        render_error(conn, error)
    end
  end

  operation(:update_consents,
    summary: "Изменить добровольные маркетинговые согласия",
    description:
      "Push по умолчанию выключен; SMS пока недоступен и true отклоняется. Настройки транзакционных уведомлений не меняются.",
    tags: ["Notifications"],
    security: [%{"bearer" => []}],
    request_body: {"Согласия", "application/json", ConsentRequest},
    responses: [
      ok: {"Согласия", "application/json", ConsentResponse},
      not_found: {"Модуль выключен", "application/json", ErrorResponse},
      unprocessable_entity: {"Неверный запрос", "application/json", ErrorResponse}
    ]
  )

  def update_consents(conn, params) do
    case Notifications.update_consents(
           client_id(conn),
           params["branch_id"],
           Map.take(params, ["sms", "push"])
         ) do
      {:ok, data} ->
        json(conn, %{data: data, capabilities: %{in_app: true, push: true, sms: false}})

      error ->
        render_error(conn, error)
    end
  end

  defp client_id(conn), do: conn.assigns.current_client.id

  defp device_id(conn, params),
    do: params["device_id"] || List.first(get_req_header(conn, "x-device-id"))

  defp render_notice(notice) do
    %{
      id: notice.id,
      title: notice.title,
      body: notice.body,
      cta: notice.cta,
      expires_at: notice.expires_at,
      created_at: notice.inserted_at
    }
  end

  defp render_error(conn, {:error, :disabled}),
    do: ApiError.send_error(conn, :not_found, :not_found, "Not found")

  defp render_error(conn, {:error, :not_found}),
    do: ApiError.send_error(conn, :not_found, :not_found, "Not found")

  defp render_error(conn, {:error, _}),
    do: ApiError.send_error(conn, :unprocessable_entity, :invalid_request, "Invalid request")
end
