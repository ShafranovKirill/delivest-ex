defmodule DelivestWeb.Client.Profile.ProfileController do
  use DelivestWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias DelivestWeb.Schemas.AuthSchemas.ProfileResponse
  alias DelivestWeb.Schemas.ErrorSchemas.ErrorResponse

  operation(:show,
    summary: "Текущий клиент",
    tags: ["Auth"],
    security: [%{"bearer" => []}],
    responses: [
      ok: {"Профиль", "application/json", ProfileResponse},
      unauthorized: {"Нужна авторизация", "application/json", ErrorResponse}
    ]
  )

  def show(conn, _params), do: render(conn, :show, client: conn.assigns.current_client)
end
