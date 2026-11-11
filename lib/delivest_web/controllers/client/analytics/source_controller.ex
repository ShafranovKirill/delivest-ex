defmodule DelivestWeb.Client.Analytics.SourceController do
  use DelivestWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Delivest.Advertising.Attribution
  alias Delivest.Features
  alias DelivestWeb.AnalyticsIdentity
  alias DelivestWeb.Helpers.ApiError
  alias DelivestWeb.Schemas.AdvertisingSourceClaimResponse
  alias DelivestWeb.Schemas.ErrorSchemas.ErrorResponse
  alias OpenApiSpex.Schema

  operation(:claim,
    summary: "Bind signed guest advertising clicks to the authenticated client",
    description:
      "Uses the signed analytics cookie and verified bearer identity. Request body must be empty.",
    tags: ["Analytics"],
    request_body:
      {"Empty request", "application/json",
       %Schema{type: :object, properties: %{}, additionalProperties: false}},
    responses: [
      ok: {"Claim result", "application/json", AdvertisingSourceClaimResponse},
      not_found: {"Advertising tracking unavailable", "application/json", ErrorResponse},
      unprocessable_entity: {"Invalid request", "application/json", ErrorResponse}
    ]
  )

  def claim(%{assigns: %{current_client: %{id: client_id}}} = conn, params) when params == %{} do
    with {:ok, generation} <- Features.snapshot("analytics_links", :franchise),
         {:ok, guest_id} <- AnalyticsIdentity.guest_id(conn),
         {:ok, {:ok, result}} <-
           Features.with_enabled("analytics_links", :franchise, generation, fn ->
             Attribution.claim(client_id, guest_id)
           end) do
      conn |> put_status(:ok) |> json(%{data: %{claimed: result.claimed}})
    else
      :error -> conn |> put_status(:ok) |> json(%{data: %{claimed: 0}})
      _ -> ApiError.send_error(conn, :not_found, :analytics_unavailable, "Analytics unavailable")
    end
  end

  def claim(conn, _),
    do: ApiError.send_error(conn, :unprocessable_entity, :invalid_event, "Invalid request")
end
