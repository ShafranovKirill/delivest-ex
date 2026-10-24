defmodule DelivestWeb.Schemas.PushSchemas do
  alias OpenApiSpex.Schema

  defmodule PushKeyResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "PushKeyResponse",
      type: :object,
      properties: %{
        data: %Schema{
          type: :object,
          properties: %{
            public_key: %Schema{type: :string, description: "VAPID public key, base64url"}
          },
          required: [:public_key]
        }
      },
      required: [:data]
    })
  end

  defmodule PushSubscriptionRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "PushSubscriptionRequest",
      type: :object,
      properties: %{
        endpoint: %Schema{type: :string, format: :uri},
        keys: %Schema{
          type: :object,
          properties: %{p256dh: %Schema{type: :string}, auth: %Schema{type: :string}},
          required: [:p256dh, :auth]
        },
        locale: %Schema{type: :string, enum: ["ru", "en"], nullable: true}
      },
      required: [:endpoint, :keys]
    })
  end
end
