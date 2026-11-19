defmodule DelivestWeb.Client.Analytics.BatchController do
  use DelivestWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Delivest.Funnel
  alias DelivestWeb.AnalyticsIdentity
  alias DelivestWeb.Helpers.ApiError
  alias DelivestWeb.Schemas.ErrorSchemas.ErrorResponse
  alias DelivestWeb.Schemas.FunnelSchemas.{BatchRequest, BatchResponse}

  operation(:create,
    summary: "Записать пакет событий воронки",
    tags: ["Analytics"],
    request_body: {"Пакет до 20 событий", "application/json", BatchRequest, required: true},
    responses: [
      accepted: {"Пакет принят", "application/json", BatchResponse},
      not_found: {"Аналитика филиала недоступна", "application/json", ErrorResponse},
      unprocessable_entity: {"Неверный пакет", "application/json", ErrorResponse},
      too_many_requests: {"Превышен лимит", "application/json", ErrorResponse}
    ]
  )

  def create(conn, %{"events" => events} = params) when map_size(params) == 1 do
    {owner, guest_id} = AnalyticsIdentity.owner(conn)

    case Funnel.capture_many(events, owner) do
      {:ok, data} ->
        conn = if guest_id, do: AnalyticsIdentity.put_guest_cookie(conn, guest_id), else: conn
        conn |> put_status(:accepted) |> json(%{data: data})

      {:error, :disabled} ->
        ApiError.send_error(conn, :not_found, :analytics_unavailable, "Analytics unavailable")

      {:error, :invalid_payload} ->
        ApiError.send_error(conn, :unprocessable_entity, :invalid_event, "Invalid event")
    end
  end

  def create(conn, _params),
    do: ApiError.send_error(conn, :unprocessable_entity, :invalid_event, "Invalid event")
end
