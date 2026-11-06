defmodule DelivestWeb.Schemas.ClientCapabilitiesResponse do
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ClientCapabilitiesResponse",
    type: :object,
    properties: %{
      api_version: %Schema{type: :integer, enum: [1]},
      order_event_version: %Schema{type: :integer, enum: [1]},
      money_unit: %Schema{type: :string, enum: ["kopeck"]},
      timestamp_format: %Schema{type: :string, enum: ["RFC3339"]},
      features: %Schema{type: :array, items: %Schema{type: :string}},
      push: %Schema{
        type: :object,
        properties: %{
          web_push: %Schema{type: :boolean},
          apns_fcm: %Schema{type: :boolean}
        },
        required: [:web_push, :apns_fcm]
      },
      deprecation: %Schema{type: :string, nullable: true}
    },
    required: [
      :api_version,
      :order_event_version,
      :money_unit,
      :timestamp_format,
      :features,
      :push,
      :deprecation
    ]
  })
end
