defmodule DelivestWeb.Schemas.FunnelSchemas.EventRequest do
  alias OpenApiSpex.Schema
  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "FunnelEventRequest",
    type: :object,
    additionalProperties: false,
    required: [:event_id, :branch_id, :event],
    properties: %{
      event_id: %Schema{type: :string, format: :uuid},
      branch_id: %Schema{type: :string, format: :uuid},
      event: %Schema{
        type: :string,
        enum: ~w(visit menu_view product_view cart_add checkout_start fulfillment_selected)
      },
      source_type: %Schema{type: :string, enum: ~w(direct campaign unknown)},
      utm_source: %Schema{type: :string, maxLength: 64, pattern: "^[a-z0-9]+(?:[-_][a-z0-9]+)*$"},
      utm_medium: %Schema{type: :string, maxLength: 64, pattern: "^[a-z0-9]+(?:[-_][a-z0-9]+)*$"},
      utm_campaign: %Schema{
        type: :string,
        maxLength: 64,
        pattern: "^[a-z0-9]+(?:[-_][a-z0-9]+)*$"
      }
    }
  })
end
