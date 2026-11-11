defmodule DelivestWeb.Schemas.NotificationSchemas.ConsentResponse do
  alias OpenApiSpex.Schema
  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "CustomerNotificationConsentResponse",
    type: :object,
    properties: %{
      data: %Schema{
        type: :object,
        properties: %{push: %Schema{type: :boolean}, sms: %Schema{type: :boolean}},
        required: [:push, :sms]
      },
      capabilities: %Schema{
        type: :object,
        properties: %{
          in_app: %Schema{type: :boolean},
          push: %Schema{type: :boolean},
          sms: %Schema{type: :boolean}
        },
        required: [:in_app, :push, :sms]
      }
    },
    required: [:data, :capabilities]
  })
end
