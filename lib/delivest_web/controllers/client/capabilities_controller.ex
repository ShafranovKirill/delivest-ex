defmodule DelivestWeb.Client.CapabilitiesController do
  use DelivestWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias DelivestWeb.Schemas.ClientCapabilitiesResponse

  operation(:show,
    summary: "Client API capabilities",
    description: "Public additive feature discovery for API version 1 clients.",
    tags: ["Client"],
    responses: [ok: {"Capabilities", "application/json", ClientCapabilitiesResponse}]
  )

  def show(conn, _params) do
    conn
    |> Plug.Conn.put_resp_header("cache-control", "no-store")
    |> json(%{
      api_version: 1,
      order_event_version: 1,
      money_unit: "kopeck",
      timestamp_format: "RFC3339",
      features: ["checkout_idempotency", "cart_revision"],
      push: %{web_push: true, apns_fcm: false},
      deprecation: nil
    })
  end
end
