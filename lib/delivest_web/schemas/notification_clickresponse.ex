defmodule DelivestWeb.Schemas.NotificationSchemas.ClickResponse do
  alias OpenApiSpex.Schema
  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "CustomerNoticeClick",
    type: :object,
    properties: %{
      data: %Schema{
        type: :object,
        nullable: true,
        properties: %{type: %Schema{type: :string}, value: %Schema{type: :string}}
      }
    },
    required: [:data]
  })
end
