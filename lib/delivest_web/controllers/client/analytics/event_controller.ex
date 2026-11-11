defmodule DelivestWeb.Client.Analytics.EventController do
  use DelivestWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Delivest.Funnel
  alias DelivestWeb.AnalyticsIdentity
  alias DelivestWeb.Helpers.ApiError
  alias DelivestWeb.Schemas.ErrorSchemas.ErrorResponse
  alias DelivestWeb.Schemas.FunnelSchemas.{EventRequest, EventResponse}

  operation(:create,
    summary: "Записать событие воронки",
    description:
      "Событие создаётся только при включённой аналитике филиала. UTM поля — непроверенные клиентские метки, не подтверждение рекламы или выручки. Гость получает отдельную подписанную cookie.",
    tags: ["Analytics"],
    request_body: {"Событие", "application/json", EventRequest, required: true},
    responses: [
      accepted: {"Событие принято", "application/json", EventResponse},
      not_found: {"Аналитика филиала недоступна", "application/json", ErrorResponse},
      unprocessable_entity: {"Неверное событие", "application/json", ErrorResponse},
      too_many_requests: {"Превышен лимит", "application/json", ErrorResponse}
    ]
  )

  def create(conn, params) do
    {owner, guest_id} = AnalyticsIdentity.owner(conn)

    case Funnel.capture(params, owner) do
      {:ok, data} ->
        conn = if guest_id, do: AnalyticsIdentity.put_guest_cookie(conn, guest_id), else: conn

        conn |> put_status(:accepted) |> json(%{data: data})

      {:error, :disabled} ->
        ApiError.send_error(conn, :not_found, :analytics_unavailable, "Analytics unavailable")

      {:error, :invalid_payload} ->
        ApiError.send_error(conn, :unprocessable_entity, :invalid_event, "Invalid event")
    end
  end
end
