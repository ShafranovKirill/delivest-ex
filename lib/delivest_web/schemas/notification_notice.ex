defmodule DelivestWeb.Schemas.NotificationSchemas.Notice do
  alias OpenApiSpex.Schema
  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "CustomerNotice",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      title: %Schema{type: :string},
      body: %Schema{type: :string},
      cta: %Schema{
        type: :object,
        nullable: true,
        properties: %{
          type: %Schema{type: :string, enum: ["apply_promo", "show_bonus"]},
          value: %Schema{type: :string}
        },
        required: [:type, :value]
      },
      expires_at: %Schema{type: :string, format: :"date-time", nullable: true},
      created_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:id, :title, :body, :created_at]
  })
end
