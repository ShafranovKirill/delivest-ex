defmodule DelivestWeb.Client.Analytics.EventController do
  use DelivestWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Delivest.Funnel
  alias DelivestWeb.{Endpoint, Helpers.ApiError, Helpers.CookieHelper}
  alias DelivestWeb.Schemas.ErrorSchemas.ErrorResponse
  alias DelivestWeb.Schemas.FunnelSchemas.{EventRequest, EventResponse}

  @cookie "analytics_owner"
  @salt "funnel_guest_owner_v1"

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
    {owner, cookie} = owner(conn)

    case Funnel.capture(params, owner) do
      {:ok, data} ->
        conn = if cookie, do: CookieHelper.put_cookie(conn, @cookie, cookie), else: conn
        conn |> put_status(:accepted) |> json(%{data: data})

      {:error, :disabled} ->
        ApiError.send_error(conn, :not_found, :analytics_unavailable, "Analytics unavailable")

      {:error, :invalid_payload} ->
        ApiError.send_error(conn, :unprocessable_entity, :invalid_event, "Invalid event")
    end
  end

  defp owner(%{assigns: %{current_client: %{id: id}}}), do: {"client:" <> id, nil}

  defp owner(conn) do
    case CookieHelper.get_cookie(conn, @cookie) do
      token when is_binary(token) ->
        case Phoenix.Token.verify(Endpoint, @salt, token, max_age: 30 * 86_400) do
          {:ok, id} ->
            case Ecto.UUID.cast(id) do
              {:ok, canonical} -> {"guest:" <> canonical, nil}
              :error -> new_guest()
            end

          _ ->
            new_guest()
        end

      _ ->
        new_guest()
    end
  end

  defp new_guest do
    id = Ecto.UUID.generate()
    {"guest:" <> id, Phoenix.Token.sign(Endpoint, @salt, id)}
  end
end
