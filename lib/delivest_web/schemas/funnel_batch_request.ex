defmodule DelivestWeb.Schemas.FunnelSchemas.BatchRequest do
  alias DelivestWeb.Schemas.FunnelSchemas.EventRequest
  alias OpenApiSpex.Schema
  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "FunnelBatchRequest",
    type: :object,
    additionalProperties: false,
    required: [:events],
    properties: %{events: %Schema{type: :array, minItems: 1, maxItems: 20, items: EventRequest}}
  })
end
