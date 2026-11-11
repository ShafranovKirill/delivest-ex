defmodule DelivestWeb.Schemas.NotificationSchemas.ConsentRequest do
  alias OpenApiSpex.Schema
  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "CustomerNotificationConsentRequest",
    type: :object,
    properties: %{
      branch_id: %Schema{type: :string, format: :uuid},
      push: %Schema{type: :boolean},
      sms: %Schema{type: :boolean, description: "Unavailable; only false accepted"}
    },
    required: [:branch_id]
  })
end
