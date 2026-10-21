defmodule DelivestWeb.Schemas.SocketSchemas do
  alias OpenApiSpex.Schema

  defmodule SocketTokenResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SocketTokenResponse",
      type: :object,
      properties: %{
        data: %Schema{
          type: :object,
          properties: %{token: %Schema{type: :string}},
          required: [:token]
        }
      },
      required: [:data]
    })
  end
end
