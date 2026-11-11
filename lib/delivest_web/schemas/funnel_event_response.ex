defmodule DelivestWeb.Schemas.FunnelSchemas.EventResponse do
  alias OpenApiSpex.Schema
  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "FunnelEventResponse",
    type: :object,
    required: [:data],
    properties: %{
      data: %Schema{
        type: :object,
        required: [:event_id, :session_id],
        properties: %{
          event_id: %Schema{type: :string, format: :uuid},
          session_id: %Schema{type: :string, format: :uuid}
        }
      }
    }
  })
end
