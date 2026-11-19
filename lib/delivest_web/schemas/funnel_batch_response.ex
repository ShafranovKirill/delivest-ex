defmodule DelivestWeb.Schemas.FunnelSchemas.BatchResponse do
  alias OpenApiSpex.Schema
  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "FunnelBatchResponse",
    type: :object,
    required: [:data],
    properties: %{
      data: %Schema{
        type: :object,
        required: [:events],
        properties: %{
          events: %Schema{
            type: :array,
            items: %Schema{
              type: :object,
              required: [:event_id, :session_id],
              properties: %{
                event_id: %Schema{type: :string, format: :uuid},
                session_id: %Schema{type: :string, format: :uuid}
              }
            }
          }
        }
      }
    }
  })
end
